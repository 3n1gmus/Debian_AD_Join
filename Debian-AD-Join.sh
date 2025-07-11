#!/bin/bash

# Ensure script is run as root
if [[ $EUID -ne 0 ]]; then
   echo "❌ This script must be run as root. Please run with sudo."
   exit 1
fi

# --- Variables ---
AD_DOMAIN=""
AD_REALM=""
DC_IP=""
AD_ADMIN=""
AD_PASS=""
PAM_FILE="/etc/pam.d/common-session"
SSSD_CONF="/etc/sssd/sssd.conf"
RESOLV_CONF="/etc/resolv.conf"
RESOLV_CONF_BACKUP="/etc/resolv.conf.bak"
SMB_CONF="/etc/samba/smb.conf"
SMB_CONF_BACKUP="/etc/samba/smb.conf.bak"

# --- Functions ---

# Function to display error and exit
function exit_on_error() {
    echo "❌ Error: $1"
    exit 1
}

# Function to prompt for user input with validation
function get_user_input() {
    local prompt_msg=$1
    local var_name=$2
    local validation_regex=$3

    while true; do
        read -rp "$prompt_msg" input
        if [[ -z "$input" ]]; then
            echo "Input cannot be empty. Please try again."
        elif [[ -n "$validation_regex" && ! "$input" =~ $validation_regex ]]; then
            echo "Invalid format. Please ensure it matches the example."
        else
            eval "$var_name='$input'"
            break
        fi
    done
}

# Function to add/update a setting in a config file
# Usage: update_config_setting "file" "section" "key" "value"
function update_config_setting() {
    local file=$1
    local section=$2
    local key=$3
    local value=$4

    # Escape forward slashes in value for sed
    local escaped_value=$(echo "$value" | sed 's/\//\\\//g')
    local escaped_key=$(echo "$key" | sed 's/\//\\\//g')

    if grep -qE "^\s*${key}\s*=" "$file"; then
        # Key exists, update it
        sed -i -E "s/^\s*${escaped_key}\s*=.*/${key} = ${escaped_value}/" "$file"
        echo "  - Updated '$key = $value' in '$file'."
    elif grep -q "\[${section}\]" "$file"; then
        # Section exists, but key doesn't, add it under the section
        sed -i "/^\[${section}\]/a ${key} = ${escaped_value}" "$file"
        echo "  - Added '$key = $value' under section '[${section}]' in '$file'."
    else
        # Neither section nor key exists, append to end
        echo -e "\n[${section}]\n${key} = ${escaped_value}" >> "$file"
        echo "  - Added section '[${section}]' and '$key = $value' to '$file'."
    fi
}


# --- Main Script ---

echo "Welcome to the Active Directory Domain Join Script for Ubuntu/Debian!"
echo "This script will help you configure your system to authenticate with an AD domain"
echo "and improve Kerberos integration for file shares."
echo ""

# Prompt for domain information
get_user_input "Enter your AD domain name (e.g., srv.world): " AD_DOMAIN "^([a-zA-Z0-9]+(-[a-zA-Z0-9]+)*\.)+[a-zA-Z]{2,}$"
get_user_input "Enter your AD realm (e.g., SRV.WORLD): " AD_REALM "^([A-Z0-9]+(-[A-Z0-9]+)*\.)+[A-Z]{2,}$"
get_user_input "Enter AD domain controller IP: " DC_IP "^((25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\.){3}(25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)$"
get_user_input "Enter AD admin user (e.g., Administrator): " AD_ADMIN
read -srp "Enter password for $AD_ADMIN: " AD_PASS
echo
echo "---"

echo "🛠️  Updating package lists and installing required packages..."
if ! apt update; then
    exit_on_error "Failed to update package lists. Check your internet connection or apt sources."
fi

# Add kio-fuse to the installation list
if ! apt -y install realmd sssd sssd-tools libnss-sss libpam-sss adcli samba-common-bin oddjob oddjob-mkhomedir kio-fuse; then
    exit_on_error "Failed to install required packages. Please check the error messages above."
fi
echo "✅ Required packages installed successfully."
echo "---"

echo "🌐 Configuring DNS..."
echo "Backing up existing $RESOLV_CONF to $RESOLV_CONF_BACKUP"
if ! cp "$RESOLV_CONF" "$RESOLV_CONF_BACKUP"; then
    exit_on_error "Failed to backup $RESOLV_CONF."
fi

echo "Setting DNS to point to the Active Directory Domain Controller."
if ! cat <<EOF > "$RESOLV_CONF"
search $AD_DOMAIN
domain $AD_DOMAIN
nameserver $DC_IP
EOF
then
    exit_on_error "Failed to write to $RESOLV_CONF. Check file permissions."
fi
echo "✅ DNS configured."
echo "---"

echo "🔍 Discovering AD domain '$AD_REALM'..."
if ! realm discover "$AD_REALM"; then
    exit_on_error "Failed to discover domain '$AD_REALM'. Please verify the domain name, DNS settings, and network connectivity to the DC."
fi
echo "✅ Domain discovered successfully."
echo "---"

echo "🔐 Attempting to join domain '$AD_REALM' as '$AD_ADMIN'..."
if ! echo "$AD_PASS" | realm join --user="$AD_ADMIN" "$AD_REALM"; then
    exit_on_error "Failed to join the domain. Common reasons include incorrect AD admin credentials, incorrect realm name, or network issues."
fi
echo "✅ Domain join successful."
echo "---"

echo "📁 Ensuring automatic home directory creation on login..."
if ! grep -q "pam_mkhomedir.so" "$PAM_FILE"; then
    echo "session optional pam_mkhomedir.so skel=/etc/skel umask=077" >> "$PAM_FILE"
    echo "✅ Added pam_mkhomedir.so to $PAM_FILE."
else
    echo "ℹ️ pam_mkhomedir.so already configured in $PAM_FILE."
fi
echo "---"

echo "🔧 Configuring SSSD for short names, offline login, and Kerberos caching..."
# Ensure SSSD config file exists
if [[ ! -f "$SSSD_CONF" ]]; then
    exit_on_error "$SSSD_CONF not found. SSSD might not be installed correctly."
fi

# Set use_fully_qualified_names
update_config_setting "$SSSD_CONF" "sssd" "use_fully_qualified_names" "False"

# Set cache_credentials
update_config_setting "$SSSD_CONF" "domain/${AD_REALM,,}" "cache_credentials" "True"

# Set offline_credentials_expiration
update_config_setting "$SSSD_CONF" "domain/${AD_REALM,,}" "offline_credentials_expiration" "0"

# Set Kerberos credential cache for graphical applications
update_config_setting "$SSSD_CONF" "domain/${AD_REALM,,}" "krb5_use_fastcc" "True"
update_config_setting "$SSSD_CONF" "domain/${AD_REALM,,}" "krb5_ccachedir" "/run/user/%U/krb5cc"

echo "✅ SSSD configured."
echo "---"

echo "🌐 Configuring Samba client for Kerberos integration..."
# Backup existing smb.conf
echo "Backing up existing $SMB_CONF to $SMB_CONF_BACKUP"
if ! cp "$SMB_CONF" "$SMB_CONF_BACKUP"; then
    echo "⚠️ Warning: Failed to backup $SMB_CONF. Continuing anyway."
fi

# Derive NetBIOS name (first part of the domain, uppercase)
NETBIOS_NAME=$(echo "$AD_DOMAIN" | cut -d'.' -f1 | tr '[:lower:]' '[:upper:]')

# Add/update global Samba settings for AD integration
echo "Updating $SMB_CONF..."
update_config_setting "$SMB_CONF" "global" "security" "ads"
update_config_setting "$SMB_CONF" "global" "kerberos method" "secrets and keytab"
update_config_setting "$SMB_CONF" "global" "realm" "$AD_REALM"
update_config_setting "$SMB_CONF" "global" "workgroup" "$NETBIOS_NAME"
update_config_setting "$SMB_CONF" "global" "client signing" "auto"
update_config_setting "$SMB_CONF" "global" "client use spnego" "yes"

echo "✅ Samba client configured for Kerberos."
echo "---"

echo "🔄 Restarting SSSD service..."
if ! systemctl restart sssd; then
    exit_on_error "Failed to restart SSSD service. Check SSSD logs for more details."
fi
echo "✅ SSSD restarted successfully."

# Restart smbd/nmbd if they are running (for samba client config)
echo "🔄 Checking and restarting Samba services (if active)..."
if systemctl is-active --quiet smbd; then
    echo "  - Restarting smbd..."
    sudo systemctl restart smbd
fi
if systemctl is-active --quiet nmbd; then
    echo "  - Restarting nmbd..."
    sudo systemctl restart nmbd
fi
echo "✅ Samba services (if active) checked/restarted."
echo "---"

echo "🎉 Configuration complete!"
echo "You should now be able to log in with Active Directory user accounts"
echo "and experience improved Kerberos-based Single Sign-On for network shares in Dolphin."
echo ""
echo "To test:"
echo "1. Log out of your desktop session and log back in as an AD user."
echo "2. Open a terminal and run 'klist' to verify Kerberos tickets."
echo "3. In Dolphin, try accessing a share (e.g., smb://your-ad-server/sharename)."
echo ""
echo "Important: Ensure your AD user has appropriate permissions to log in to Linux systems and access shares."
echo "If you encounter issues, check the system logs (e.g., journalctl -xe or /var/log/syslog) and SSSD logs (/var/log/sssd/)."
echo ""

exit 0