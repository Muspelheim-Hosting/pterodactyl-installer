#!/bin/bash

set -e

######################################################################################
#                                                                                    #
# Project 'pyrodactyl-installer'                                                     #
#                                                                                    #
# Copyright (C) 2018 - 2026, Vilhelm Prytz, <vilhelm@prytznet.se>                    #
#                                                                                    #
#   This program is free software: you can redistribute it and/or modify             #
#   it under the terms of the GNU General Public License as published by             #
#   the Free Software Foundation, either version 3 of the License, or                #
#   (at your option) any later version.                                              #
#                                                                                    #
#   This program is distributed in the hope that it will be useful,                  #
#   but WITHOUT ANY WARRANTY; without even the implied warranty of                   #
#   MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the                    #
#   GNU General Public License for more details.                                     #
#                                                                                    #
#   You should have received a copy of the GNU General Public License                #
#   along with this program.  If not, see <https://www.gnu.org/licenses/>.           #
#                                                                                    #
# https://github.com/Muspelheim-Hosting/pterodactyl-installer/blob/master/LICENSE    #
#                                                                                    #
# Based on pterodactyl-installer by Vilhelm Prytz. Not an official project.          #
# https://github.com/Muspelheim-Hosting/pterodactyl-installer                        #
#                                                                                    #
######################################################################################

# Check if script is loaded, load if not or fail otherwise.
fn_exists() { declare -F "$1" >/dev/null; }
if ! fn_exists lib_loaded; then
  # shellcheck source=lib/lib.sh
  source /tmp/pyrodactyl-lib.sh || source <(curl -sSL "$GITHUB_BASE_URL/$GITHUB_SOURCE"/lib/lib.sh)
  ! fn_exists lib_loaded && echo "* ERROR: Could not load lib script" && exit 1
fi

# ------------------ Variables ----------------- #

INSTALL_MARIADB="${INSTALL_MARIADB:-false}"

# firewall
CONFIGURE_FIREWALL="${CONFIGURE_FIREWALL:-false}"

# SSL (Let's Encrypt)
CONFIGURE_LETSENCRYPT="${CONFIGURE_LETSENCRYPT:-false}"
FQDN="${FQDN:-}"
EMAIL="${EMAIL:-}"

# Rustic backup tool (deduplicated, encrypted backups) — optional but recommended by Pyrodactyl
CONFIGURE_RUSTIC="${CONFIGURE_RUSTIC:-true}"

# Database host
CONFIGURE_DBHOST="${CONFIGURE_DBHOST:-false}"
CONFIGURE_DB_FIREWALL="${CONFIGURE_DB_FIREWALL:-false}"
MYSQL_DBHOST_HOST="${MYSQL_DBHOST_HOST:-127.0.0.1}"
MYSQL_DBHOST_USER="${MYSQL_DBHOST_USER:-pyrodactyluser}"
MYSQL_DBHOST_PASSWORD="${MYSQL_DBHOST_PASSWORD:-}"

if [[ $CONFIGURE_DBHOST == true && -z "${MYSQL_DBHOST_PASSWORD}" ]]; then
  error "Mysql database host user password is required"
  exit 1
fi

# ----------- Installation functions ----------- #

enable_services() {
  [ "$INSTALL_MARIADB" == true ] && systemctl enable mariadb
  [ "$INSTALL_MARIADB" == true ] && systemctl start mariadb
  systemctl start docker
  systemctl enable docker
}

dep_install() {
  output "Installing dependencies for $OS $OS_VER..."

  [ "$CONFIGURE_FIREWALL" == true ] && install_firewall && firewall_ports

  case "$OS" in
  ubuntu | debian)
    install_packages "ca-certificates gnupg lsb-release"

    mkdir -p /etc/apt/keyrings
    curl -fsSL https://download.docker.com/linux/debian/gpg | gpg --dearmor --yes -o /etc/apt/keyrings/docker.gpg

    echo \
      "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/$OS \
      $(lsb_release -cs) stable" | tee /etc/apt/sources.list.d/docker.list >/dev/null
    ;;

  rocky | almalinux)
    install_packages "dnf-utils"
    dnf config-manager --add-repo=https://download.docker.com/linux/centos/docker-ce.repo

    [ "$CONFIGURE_LETSENCRYPT" == true ] && install_packages "epel-release"

    install_packages "device-mapper-persistent-data lvm2"
    ;;
  esac

  # Update the new repos
  update_repos

  # Install dependencies (buildx + compose plugins and tar per the Elytra install guide)
  install_packages "docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin tar"

  # Install mariadb if needed
  [ "$INSTALL_MARIADB" == true ] && install_packages "mariadb-server"
  [ "$CONFIGURE_LETSENCRYPT" == true ] && install_packages "certbot"

  enable_services

  success "Dependencies installed!"
}

elytra_dl() {
  echo "* Downloading Pyrodactyl Elytra.. "

  mkdir -p /etc/elytra
  curl -L -o /usr/local/bin/elytra "$ELYTRA_DL_BASE_URL$ARCH"

  chmod u+x /usr/local/bin/elytra

  success "Pyrodactyl Elytra downloaded successfully"
}

# Elytra provisions a 'pyrodactyl' system user on first start and can fail to do so in
# some environments (logged as "failed to create pyrodactyl system user error=exit status 4").
# Pre-creating the account avoids that failure.
create_elytra_user() {
  if getent passwd pyrodactyl >/dev/null 2>&1; then
    output "System user 'pyrodactyl' already exists, skipping."
    return 0
  fi

  output "Creating 'pyrodactyl' system user for Elytra.."
  useradd --system --create-home --shell /usr/sbin/nologin \
    --comment "Elytra/Pyrodactyl system user" pyrodactyl

  success "Created 'pyrodactyl' system user."
}

# Rustic gives Elytra deduplicated, encrypted backups. Optional, but recommended.
# Failure here is non-fatal: Elytra runs without it (you just lose dedup/encrypted backups).
install_rustic() {
  output "Installing rustic (deduplicated, encrypted backups).."

  if [ -x "$(command -v rustic)" ]; then
    success "rustic is already installed, skipping."
    return 0
  fi

  local rustic_arch
  case "$ARCH" in
  amd64) rustic_arch="x86_64" ;;
  arm64) rustic_arch="aarch64" ;;
  *)
    warning "Unknown architecture '$ARCH'; skipping rustic install."
    return 0
    ;;
  esac

  local rustic_version
  rustic_version=$(get_latest_release "rustic-rs/rustic")
  if [ -z "$rustic_version" ]; then
    rustic_version="v0.10.0"
    warning "Could not determine the latest rustic version; falling back to $rustic_version"
  fi

  output "Downloading rustic $rustic_version.."
  if ! curl -fsSL -o /tmp/rustic.tar.gz \
    "https://github.com/rustic-rs/rustic/releases/download/${rustic_version}/rustic-${rustic_version}-${rustic_arch}-unknown-linux-musl.tar.gz"; then
    warning "Failed to download rustic; continuing without it."
    return 0
  fi

  tar -xzf /tmp/rustic.tar.gz -C /usr/local/bin rustic
  chmod +x /usr/local/bin/rustic
  rm -f /tmp/rustic.tar.gz

  success "rustic installed!"
}

systemd_file() {
  output "Installing systemd service.."

  curl -o /etc/systemd/system/elytra.service "$GITHUB_URL"/configs/elytra.service
  systemctl daemon-reload
  systemctl enable elytra

  success "Installed systemd service!"
}

firewall_ports() {
  output "Opening port 22 (SSH), 8080 (Elytra Port), 2022 (Elytra SFTP Port)"

  [ "$CONFIGURE_LETSENCRYPT" == true ] && firewall_allow_ports "80 443"
  [ "$CONFIGURE_DB_FIREWALL" == true ] && firewall_allow_ports "3306"

  firewall_allow_ports "22"
  output "Allowed port 22"
  firewall_allow_ports "8080"
  output "Allowed port 8080"
  firewall_allow_ports "2022"
  output "Allowed port 2022"

  success "Firewall ports opened!"
}

letsencrypt() {
  FAILED=false

  output "Configuring LetsEncrypt.."

  # If user has nginx
  systemctl stop nginx || true

  # Obtain certificate
  certbot certonly --no-eff-email --email "$EMAIL" --standalone -d "$FQDN" || FAILED=true

  systemctl start nginx || true

  # Check if it succeded
  if [ ! -d "/etc/letsencrypt/live/$FQDN/" ] || [ "$FAILED" == true ]; then
    warning "The process of obtaining a Let's Encrypt certificate failed!"
  else
    success "The process of obtaining a Let's Encrypt certificate succeeded!"
  fi
}

configure_mysql() {
  output "Configuring MySQL.."

  create_db_user "$MYSQL_DBHOST_USER" "$MYSQL_DBHOST_PASSWORD" "$MYSQL_DBHOST_HOST"
  grant_all_privileges "*" "$MYSQL_DBHOST_USER" "$MYSQL_DBHOST_HOST"

  if [ "$MYSQL_DBHOST_HOST" != "127.0.0.1" ]; then
    echo "* Changing MySQL bind address.."

    case "$OS" in
    debian | ubuntu)
      sed -i 's/127.0.0.1/0.0.0.0/g' /etc/mysql/mariadb.conf.d/50-server.cnf
      ;;
    rocky | almalinux)
      sed -ne 's/^#bind-address=0.0.0.0$/bind-address=0.0.0.0/' /etc/my.cnf.d/mariadb-server.cnf
      ;;
    esac

    systemctl restart mysqld
  fi

  success "MySQL configured!"
}

# --------------- Main functions --------------- #

perform_install() {
  output "Installing Pyrodactyl Elytra.."
  dep_install
  create_elytra_user
  elytra_dl
  [ "$CONFIGURE_RUSTIC" == true ] && install_rustic
  systemd_file
  [ "$CONFIGURE_DBHOST" == true ] && configure_mysql
  [ "$CONFIGURE_LETSENCRYPT" == true ] && letsencrypt

  return 0
}

# ---------------- Installation ---------------- #

perform_install
