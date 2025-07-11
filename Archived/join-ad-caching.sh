#!/bin/bash

# Ensure script is run as root
if [[ $EUID -ne 0 ]]; then
   echo "❌ This script must be run as root." 
   exit 1
fi

# Prompt for domain information
read -rp "Enter your AD domain name (e.g., srv.world): " AD_DOMAIN
read -rp "Enter your AD realm (e.g., SRV.WORLD): " AD_REALM
read -rp "Enter AD domain controller IP: " DC_IP
read -rp "Enter AD admin user (e.g., Administrator): " AD_ADMIN
read -srp "Enter password for $AD_ADMIN: " AD_PASS
echo

echo "🛠️  Installing required packages..."
apt update && apt -y install realmd sssd sssd-tools libnss-sss libpam-sss adcli samba-common-bin oddjob oddjob-mkhomedir packagekit

echo "🌐 Configuring DNS..."
# Backup existing resolv.conf
cp /etc/resolv.conf /etc/resolv.conf.bak
cat <<EOF > /etc/resolv.conf
search $AD_DOMAIN
domain $AD_DOMAIN
nameserver $DC_IP
EOF

echo "🔍 Discovering AD domain..."
realm discover "$AD_REALM"
if [[ $? -ne 0 ]]; then
    echo "❌ Failed to discover domain. Check DNS settings."
    exit 1
fi

echo "🔐 Joining domain..."
echo "$AD_PASS" | realm join --user="$AD_ADMIN" "$AD_REALM"
if [[ $? -ne 0 ]]; then
    echo "❌ Failed to join the domain."
    exit 1
fi

echo "✅ Domain join successful."

echo "📁 Enabling automatic home directory creation on login..."
pam_file="/etc/pam.d/common-session"
grep -q pam_mkhomedir.so "$pam_file" || echo "session optional pam_mkhomedir.so skel=/etc/skel umask=077" >> "$pam_file"

echo "🔧 Configuring SSSD for short names (omit domain)..."
sssd_conf="/etc/sssd/sssd.conf"
if grep -q "use_fully_qualified_names" "$sssd_conf"; then
    sed -i 's/use_fully_qualified_names = .*/use_fully_qualified_names = False/' "$sssd_conf"
else
    echo "use_fully_qualified_names = False" >> "$sssd_conf"
fi

echo "🔧 Enabling offline login (SSSD cache credentials)..."
# Ensure offline credentials are cached and never expire
if grep -q "cache_credentials" "$sssd_conf"; then
    sed -i 's/cache_credentials = .*/cache_credentials = True/' "$sssd_conf"
else
    echo "cache_credentials = True" >> "$sssd_conf"
fi

if grep -q "offline_credentials_expiration" "$sssd_conf"; then
    sed -i 's/offline_credentials_expiration = .*/offline_credentials_expiration = 0/' "$sssd_conf"
else
    echo "offline_credentials_expiration = 0" >> "$sssd_conf"
fi

echo "🔄 Restarting SSSD..."
systemctl restart sssd

echo "✅ Configuration complete. You can now log in with AD user accounts even when offline."

