#!/bin/bash

# === Ensure sudo password is cached ===
echo "This script needs sudo privileges. You may be prompted for your password."
sudo -v || { echo "Failed to authenticate with sudo"; exit 1; }

# === Install software by OS type ===
os_name=$(hostnamectl | awk -F: '/Operating System/ {print $2}' | xargs)

case "$os_name" in
    *Debian*|*Ubuntu*|*Linux\ Mint*|*Kali*|*Pop!\_OS*|*PikaOS*)
        echo "Debian family detected → $os_name"
        os_family="debian"
        sudo apt-get update && sudo apt-get install -y realmd sssd sssd-tools libnss-sss libpam-sss adcli samba-common-bin packagekit krb5-user libpam-krb5 libpam-ccreds libpam-mkhomedir gvfs-backends kio-extras
        ;;
    *Fedora*|*Red\ Hat*|*CentOS*|*Rocky*|*AlmaLinux*)
        echo "Fedora family detected → $os_name"
        echo "Install Unsupported"
        os_family="fedora"
        exit 1
        ;;
    *Arch*|*Manjaro*|*EndeavourOS*|*ArcoLinux*|*CachyOS*)
        echo "Arch family detected → $os_name"
        os_family="arch"
        sudo pacman -Syu --needed sssd ntp pam-krb5 samba yay
        yay -S realmd
        ;;
    *)
        echo "Unknown or unsupported OS: $os_name"
        echo "Install Unsupported"
        os_family="unknown"
        exit 1
        ;;
esac

# === Interactive prompts for variables ===
read -rp "Enter AD base domain (e.g. hyrule.synthrealm.net): " AD_BASE
read -rp "Enter comma-separated domain controllers (e.g. dc1.hyrule.synthrealm.net,dc2.hyrule.synthrealm.net): " AD_SERVERS
read -rp "Enter domain admin username for joining (e.g. Administrator): " AD_ADMIN

# === Derived variables ===
DOMAIN="${AD_BASE,,}"   # lowercase for DNS
REALM="${AD_BASE^^}"    # uppercase for Kerberos

# Keep sudo alive while script runs
while true; do sudo -n true; sleep 60; kill -0 "$$" || exit; done 2>/dev/null &

# === Install required packages in one line ===
# sudo apt-get update && sudo apt-get install -y realmd sssd sssd-tools libnss-sss libpam-sss adcli samba-common-bin packagekit krb5-user libpam-krb5 libpam-ccreds libpam-mkhomedir

# === Discover AD domain ===
sudo realm discover "$DOMAIN"

# === Join the domain using the first reachable DC ===
echo "Joining domain $DOMAIN..."
sudo realm join --verbose --user="$AD_ADMIN@$REALM" "$REALM"

if [ $? -ne 0 ]; then
  echo "Failed to join $DOMAIN"
  exit 1
fi

# === Configure SSSD with credential caching, short usernames, multiple DCs, offline login ===
sudo bash -c "cat >/etc/sssd/sssd.conf" <<EOF
[sssd]
domains = $DOMAIN
services = nss, pam

[domain/$DOMAIN]
ad_domain = $DOMAIN
krb5_realm = $REALM
ad_server = $AD_SERVERS
realmd_tags = manages-system joined-with-adcli
cache_credentials = True
id_provider = ad
access_provider = ad
krb5_ccname_template = KEYRING:persistent:%U

# Username & home dir settings
use_fully_qualified_names = False
fallback_homedir = /home/%u
default_shell = /bin/bash
EOF

sudo chmod 600 /etc/sssd/sssd.conf

# === Enable and restart SSSD ===
sudo systemctl enable sssd
sudo systemctl restart sssd

# === Configure PAM to auto-create home directories ===
sudo pam-auth-update --enable mkhomedir

# === Generate krb5.conf ===
KRBCONF="/etc/krb5.conf"
sudo mv "$KRBCONF" "${KRBCONF}.bak"
echo "Generating new krb5.conf..."
sudo tee "$KRBCONF" > /dev/null <<EOF
[libdefaults]
    default_realm = $REALM
    rdns = false
    default_ccache_name = KEYRING:persistent:%{uid}
EOF

# === Sanity check ===
echo "=== SANITY CHECK ==="
echo "SSSD status:"
systemctl status sssd --no-pager

# SSSD config sanity check
echo "==> Running sssctl config-check..."
if ! sudo sssctl config-check; then
  echo "ERROR: SSSD config check failed!"
  exit 1
fi

echo "Realm list:"
realm list

echo "Attempting kinit with AD admin..."
kinit "$AD_ADMIN@$REALM" && klist || echo "Kerberos credentials check failed"

echo "=== SUCCESS ==="
echo "System $(hostname -s) is now joined to $DOMAIN ($REALM)"
echo "Users can now log in with short usernames (e.g. 'jdoe' instead of 'jdoe@$DOMAIN')."
echo "Home directories will be created automatically using pam_mkhomedir."
echo "SSSD is configured to use multiple domain controllers: $AD_SERVERS"
