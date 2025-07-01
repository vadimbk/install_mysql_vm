#!/bin/bash
set -e

# This script is intended for Ubuntu systems only.
# It will exit if the detected OS is not Ubuntu.
if ! grep -qi ubuntu /etc/os-release; then
  echo "Error: This script supports only Ubuntu. Exiting."
  exit 1
fi

# CONFIGURATION PARAMETERS - SET THEM MANUALLY BELOW
ALLOWED_SUBNET="10.0.0.0/24"              # Subnet allowed to connect to MySQL
MYSQL_ROOT_PASSWORD="MyStrongRootPass"    # MySQL root password
NEW_DB_USER="dbuser"                      # New database user
NEW_DB_USER_PASSWORD="MyStrongDbPass"     # New user password
SUDO_USER_NAME="admin"                    # Sudo username
SUDO_USER_PASSWORD="MySudoPass"           # Sudo password
TIMEZONE="Europe/Berlin"                  # Timezone to set
HOSTNAME="dbcontainer01"                  # Hostname to set

if [[ -z "$ALLOWED_SUBNET" ]]; then
    echo "Error: ALLOWED_SUBNET is not set. Exiting."
    exit 1
fi

apt-get update && apt-get -y full-upgrade
apt-get install -y mc vim mysql-server htop whois traceroute unattended-upgrades sudo mysqltuner

# Configure unattended-upgrades for security updates only
cat > /etc/apt/apt.conf.d/50unattended-upgrades <<EOF
Unattended-Upgrade::Origins-Pattern {
        "origin=Debian,codename=\${distro_codename},label=Debian-Security";
        "origin=Ubuntu,codename=\${distro_codename},label=Ubuntu";
};
Unattended-Upgrade::Mail "root";
Unattended-Upgrade::Remove-Unused-Dependencies "true";
Unattended-Upgrade::Automatic-Reboot "true";
Unattended-Upgrade::Automatic-Reboot-Time "04:00";
EOF

cat > /etc/apt/apt.conf.d/20auto-upgrades <<EOF
APT::Periodic::Update-Package-Lists "1";
APT::Periodic::Unattended-Upgrade "1";
EOF

# Generate locale for consistent UTF-8 support
locale-gen en_US.UTF-8
cat <<EOT > /etc/default/locale
LANG="en_US.UTF-8"
LC_ALL="en_US.UTF-8"
LANGUAGE="en_US:en"
EOT

# Set timezone and hostname
timedatectl set-timezone ${TIMEZONE}
echo "Timezone set to ${TIMEZONE}"
hostnamectl set-hostname ${HOSTNAME}
echo "Hostname set to ${HOSTNAME}"

# Calculate optimal InnoDB buffer pool settings based on total memory
MEM_TOTAL_MB=$(awk '/MemTotal/ {print int($2/1024)}' /proc/meminfo)
echo "Detected memory: ${MEM_TOTAL_MB} MB"

BUFFER_POOL_MB=$((MEM_TOTAL_MB * 75 / 100))
MAX_POOL_MB=$((MEM_TOTAL_MB * 80 / 100))
if [ $BUFFER_POOL_MB -gt $MAX_POOL_MB ]; then BUFFER_POOL_MB=$MAX_POOL_MB; fi

BUFFER_INSTANCES=1
if [ $BUFFER_POOL_MB -ge 1024 ] && [ $BUFFER_POOL_MB -le 8192 ]; then
  BUFFER_INSTANCES=2
elif [ $BUFFER_POOL_MB -gt 8192 ]; then
  BUFFER_INSTANCES=$((BUFFER_POOL_MB / 1024))
  [ $BUFFER_INSTANCES -gt 8 ] && BUFFER_INSTANCES=8
fi

echo "Configured InnoDB: buffer_pool=${BUFFER_POOL_MB}M, instances=${BUFFER_INSTANCES}"

cat > /etc/mysql/mysql.conf.d/mysqld.cnf <<EOF
# MySQL server configuration file.
# This server is configured as a standalone MySQL instance with external access enabled,
# restricted by firewall to the internal cluster subnet.
[mysqld]
user = mysql
pid-file = /var/run/mysqld/mysqld.pid
socket = /var/run/mysqld/mysqld.sock
port = 3306
datadir = /var/lib/mysql
bind-address = 0.0.0.0  # Allow external connections (restricted by UFW)
mysqlx=OFF

# InnoDB buffer pool configuration
innodb_buffer_pool_size = ${BUFFER_POOL_MB}M
innodb_buffer_pool_instances = ${BUFFER_INSTANCES}
innodb_log_file_size = 640M
innodb_log_buffer_size = 128M
innodb_flush_log_at_trx_commit = 1
sync_binlog = 1
innodb_flush_method = O_DIRECT

# Temporary tables and join buffers
tmp_table_size = 128M
max_heap_table_size = 128M
sort_buffer_size = 4M
join_buffer_size = 4M
read_buffer_size = 2M
read_rnd_buffer_size = 2M

# Connections and caches
max_connections = 150
table_open_cache = 400
open_files_limit = 2000

# Logging and modes
log_error = /var/log/mysql/error.log
skip-name-resolve = ON
sql_mode = "STRICT_TRANS_TABLES,ERROR_FOR_DIVISION_BY_ZERO,NO_ENGINE_SUBSTITUTION"
EOF

systemctl restart mysql

mysql -u root <<EOS
DELETE FROM mysql.user WHERE User='';
DELETE FROM mysql.user WHERE User='root' AND Host NOT IN ('localhost');
DROP DATABASE IF EXISTS test;
DELETE FROM mysql.db WHERE Db='test' OR Db='test\\_%';
ALTER USER 'root'@'localhost' IDENTIFIED WITH caching_sha2_password BY '${MYSQL_ROOT_PASSWORD}';
FLUSH PRIVILEGES;
EOS

mysql -u root -p"${MYSQL_ROOT_PASSWORD}" -e "SELECT 1;" >/dev/null 2>&1 || { echo "Error: Cannot connect with new root password."; exit 1; }

mysql -u root -p"${MYSQL_ROOT_PASSWORD}" <<EOS
CREATE USER IF NOT EXISTS '${NEW_DB_USER}'@'${ALLOWED_SUBNET}' IDENTIFIED BY '${NEW_DB_USER_PASSWORD}';
GRANT ALL PRIVILEGES ON *.* TO '${NEW_DB_USER}'@'${ALLOWED_SUBNET}' WITH GRANT OPTION;
FLUSH PRIVILEGES;
EOS

# Note: UFW applies these rules for both IPv4 and IPv6 by default.
# Setup UFW firewall: allow SSH from anywhere to avoid lockout on VMs, but restrict MySQL to ALLOWED_SUBNET.
ufw default deny incoming
ufw default allow outgoing
ufw allow 22/tcp comment 'Allow SSH from anywhere (VM safety)'
ufw allow from ${ALLOWED_SUBNET} to any port 3306 proto tcp comment 'Allow MySQL from allowed subnet'
ufw --force enable
ufw status verbose

# Disable SSH login for root to force using the sudo user
sed -i 's/^PermitRootLogin.*/PermitRootLogin no/' /etc/ssh/sshd_config
if systemctl is-active --quiet ssh; then
  systemctl reload ssh
else
  echo "Warning: SSH service is not active, skipping reload."
fi

useradd -m -s /bin/bash ${SUDO_USER_NAME}
echo "${SUDO_USER_NAME}:${SUDO_USER_PASSWORD}" | chpasswd
usermod -aG sudo ${SUDO_USER_NAME}
usermod -aG sudo root
echo "Sudo user '${SUDO_USER_NAME}' created and added to sudo group."

cat <<EOF > ~/.vimrc
syntax on
set encoding=utf-8
set fileencoding=utf-8
set formatoptions-=cro
EOF

echo 'export TERM=xterm-256color' >> ~/.bashrc
cp /root/.vimrc /home/${SUDO_USER_NAME}/.vimrc
echo 'export TERM=xterm-256color' >> /home/${SUDO_USER_NAME}/.bashrc
chown ${SUDO_USER_NAME}:${SUDO_USER_NAME} /home/${SUDO_USER_NAME}/.vimrc /home/${SUDO_USER_NAME}/.bashrc

echo "MysSQL installation and configuration completed successfully!"
