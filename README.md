# Debian/Ubuntu Active Directory Domain Join & Unjoin Scripts

This repository provides two comprehensive Bash scripts to manage your Ubuntu or Debian system's integration with an Active Directory (AD) domain.

## 1\. `Debian-AD-Join.sh` (Domain Join Script)

This script automates the process of joining an Ubuntu or Debian system to an Active Directory (AD) domain. Beyond basic domain integration, it includes crucial configurations to ensure seamless **Kerberos-based Single Sign-On (SSO)** for accessing SMB/CIFS network shares, particularly beneficial for desktop environments like KDE Plasma (e.g., with Dolphin file manager).

### Features

  * **Automated Package Installation:** Installs all necessary packages, including `realmd`, `sssd`, `adcli`, and `kio-fuse` (for enhanced KDE integration).
  * **DNS Configuration:** Automatically sets up `/etc/resolv.conf` to point to your Active Directory Domain Controller for proper name resolution.
  * **Domain Discovery & Join:** Utilizes `realm` to discover and join your specified AD domain using provided administrator credentials.
  * **Automatic Home Directory Creation:** Configures `pam_mkhomedir.so` to automatically create home directories for AD users upon their first login.
  * **SSSD Configuration for SSO:**
      * Enables **short name logins** (e.g., `username` instead of `username@REALM.COM`).
      * Configures **offline login** by caching AD credentials.
      * Sets up **Kerberos credential caching (`krb5_use_fastcc` and `krb5_ccachedir`)** for graphical applications, enabling true Single Sign-On for network resources.
  * **Samba Client (SMB) Integration:**
      * Configures `/etc/samba/smb.conf` to explicitly use **Active Directory Security (ADS)** and Kerberos for client-side authentication.
      * Automatically derives the NetBIOS name for the `workgroup` setting.
      * Enables Kerberos-specific settings like `client signing` and `client use spnego` for robust Kerberos ticket usage.
  * **Robust Error Handling:** Includes checks and clear error messages at each critical step, ensuring that failures are immediately reported.
  * **Configuration File Backups:** Creates backups of `/etc/resolv.conf` and `/etc/samba/smb.conf` before making changes.
  * **Clear User Prompts & Feedback:** Provides interactive prompts for necessary information and displays informative messages throughout the execution.

### Why Use This Script?

While `realmd` simplifies the domain join process, achieving true Kerberos-based SSO for network shares (especially in desktop environments like KDE) often requires additional configuration of SSSD and Samba. This script automates these crucial extra steps, saving time and preventing common troubleshooting headaches.

If you've experienced scenarios where you could log into your Linux machine with AD credentials but still had to re-enter them when accessing network shares in Dolphin or other file managers, this script aims to resolve that by ensuring your Kerberos tickets are properly utilized across the system.

### Usage

1.  **Download the script:**

    ```bash
    wget https://raw.githubusercontent.com/3n1gmus/Debian_AD_Join/main/Debian-AD-Join.sh
    # Or just clone the repository and navigate to the script
    ```

2.  **Make the script executable:**

    ```bash
    chmod +x Debian-AD-Join.sh
    ```

3.  **Run the script with `sudo`:**

    ```bash
    sudo ./Debian-AD-Join.sh
    ```

    The script will then guide you through providing the necessary Active Directory information (domain name, realm, DC IP, admin user, and password).

### Post-Execution Steps

After the script completes:

1.  **Log out** of your current desktop session (if applicable) and **log back in** as an AD user.
2.  **Verify Kerberos tickets** by opening a terminal and running:
    ```bash
    klist
    ```
    You should see tickets for your AD user and the Kerberos Ticket Granting Ticket (`krbtgt`).
3.  **Test accessing network shares** in your file manager (e.g., Dolphin). You should no longer be prompted for credentials when accessing shares that your AD user has permissions for. Try paths like `smb://your-ad-server/sharename`.

-----

## 2\. `Debian-AD-Unjoin.sh` (Domain Unjoin Script)

This script is designed to safely and systematically unjoin an Ubuntu or Debian system from an Active Directory domain and revert most of the configuration changes made by the join script.

### Features

  * **Automated Domain Unjoin:** Uses `realm leave` to remove the system from the AD domain.
  * **Intelligent Realm Discovery:** Attempts to automatically detect the currently joined realm, or prompts you if it can't.
  * **SSSD Cleanup:** Stops the `sssd` service, clears SSSD's cache and logs, and removes the `sssd.conf` file.
  * **PAM Module Reversion:** Removes the `pam_mkhomedir.so` line from `/etc/pam.d/common-session`.
  * **Configuration File Restoration:** Restores `/etc/resolv.conf` and `/etc/samba/smb.conf` from the backups created by the join script.
  * **Samba Service Restart:** Restarts `smbd` and `nmbd` services (if active) to apply reverted Samba configurations.
  * **Optional Package Removal:** Offers to purge `realmd`, `sssd`, `adcli`, and `kio-fuse` packages, along with an `apt autoremove` for a cleaner system.
  * **Safety Confirmation:** Prompts for confirmation before initiating the unjoin process due to its significant system impact.
  * **Clear Progress & Warnings:** Provides informative messages and warnings throughout the unjoin process.

### Why Use This Script?

If you need to remove a system from an Active Directory domain, doing so manually can involve several steps across different configuration files. This script streamlines the unjoin process, helping to ensure a clean detachment from the domain and restoring common system settings to their pre-join state. It's particularly useful for testing, decommissioning, or repurposing systems.

### Usage

1.  **Download the script:**

    ```bash
    wget https://raw.githubusercontent.com/3n1gmus/Debian_AD_Join/main/Debian-AD-Unjoin.sh
    # Or just clone the repository and navigate to the script
    ```

2.  **Make the script executable:**

    ```bash
    chmod +x Debian-AD-Unjoin.sh
    ```

3.  **Run the script with `sudo`:**

    ```bash
    sudo ./Debian-AD-Unjoin.sh
    ```

    The script will ask for confirmation before proceeding and may prompt for the AD realm if it cannot be automatically detected.

### Post-Execution Steps

After the script completes:

1.  **Reboot your system** for all changes to fully take effect.
2.  **Ensure you can log in with a local user account** after reboot. Active Directory user accounts will no longer be able to log in.
3.  If you chose to remove packages, you might need to manually clean up any remaining empty configuration directories in `/etc/sssd/` or `/etc/realmd/` if they exist.

-----

## Troubleshooting (Common to Both Scripts)

  * **DNS Issues:** If `realm discover` (in join) or unjoin issues arise, double-check the AD Domain Controller IP address and ensure your Linux machine has network connectivity to it.
  * **Credential Issues:** If `realm join` fails, verify the AD admin username and password.
  * **SSSD Logs:** For authentication or lookup problems, check SSSD logs:
    ```bash
    sudo journalctl -u sssd.service
    # Or directly in /var/log/sssd/
    ```
  * **System Logs:** For general issues, review system logs:
    ```bash
    sudo journalctl -xe
    # Or /var/log/syslog
    ```

-----