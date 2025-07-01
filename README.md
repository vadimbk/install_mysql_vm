# Ubuntu MySQL Server Setup Script for Internal Clusters

This repository provides an automated Bash script for deploying and configuring a standalone MySQL 8 server on Ubuntu 20.04, 22.04, or 24.04. This script is specifically designed for virtual machines (VMs) or containers operating in a mini-cluster connected to a private internal network, such as a Proxmox cluster or a private cloud environment.

---

## Purpose

The script configures MySQL as a dedicated database node with external connections restricted to your trusted internal subnet, ensuring performance, security, and reliability when multiple VMs or containers communicate over an isolated LAN.

---

## Key Features

* **MySQL 8 Installation:** Installs MySQL 8 and essential administration tools.
* **Optimized Performance:** Dynamically calculates optimal InnoDB buffer pool size and instances based on system memory for better performance.
* **Locale & Timezone:** Configures system locale (`en_US.UTF-8`) for UTF-8 compatibility and sets the desired timezone and hostname.
* **Secure MySQL Access:**
    * Secures the MySQL `root` account with your chosen password.
    * Creates a dedicated MySQL user with access limited to your specified subnet.
* **Automated Updates:** Enables unattended security updates to keep your system patched.
* **UFW Firewall Configuration:**
    * **SSH:** Open globally by default to prevent lockout during initial setup.
    * **MySQL:** Restricted to your internal subnet.
* **Enhanced SSH Security:** Disables direct SSH login for `root`, enforcing access through your configured sudo user.
* **Performance Analysis Tool:** Installs `mysqltuner` for ongoing performance recommendations.
* **Developer-Friendly Environment:** Configures **Vim** and Bash environments for both `root` and the sudo user, streamlining your workflow.

---

## Intended Use

This script is intended for private clusters, where VMs or containers share a secure, isolated subnet. **It is not intended for public servers without additional hardening.**

---

## Usage

1.  **Clone or Copy:** Get this script onto your Ubuntu VM or container.
2.  **Edit Configuration:** Open the script (you can use `vim`!) and modify the configuration parameters at the top:
    * `ALLOWED_SUBNET`: Your internal subnet allowed to access MySQL (e.g., `10.101.0.0/24`).
    * `MYSQL_ROOT_PASSWORD`: The password for the MySQL `root` user.
    * `NEW_DB_USER` / `NEW_DB_USER_PASSWORD`: Credentials for your application user.
    * `SUDO_USER_NAME` / `SUDO_USER_PASSWORD`: Credentials for a new sudo-enabled system user.
    * `TIMEZONE` / `HOSTNAME`: Desired system timezone and hostname.
3.  **Make Executable:**
    ```bash
    chmod +x setup-mysql.sh
    ```
4.  **Run with Root Privileges:**
    ```bash
    sudo ./setup-mysql.sh
    ```

---

## After Completion

Once the script finishes:

* MySQL will be configured with memory settings optimized for your hardware.
* MySQL will only allow connections from your specified internal subnet.
* Direct SSH login for `root` will be disabled; use your configured `sudo` user for SSH access.

---

### Important Notes

* **SSH Access:** By default, SSH is open from anywhere (`ufw allow 22/tcp`) to avoid accidental lockout on VMs. Review and tighten your firewall rules if stricter SSH access is needed after setup.
* **MySQL Network Binding:** MySQL is configured to listen on all interfaces (`0.0.0.0`), but UFW ensures connections are only possible from your `ALLOWED_SUBNET`.
* **Root SSH:** The script disables direct `root` SSH login to enforce using your `sudo` user for administrative tasks, which is a security best practice.

---

## Support

For questions or issues, please open an issue in this repository.
