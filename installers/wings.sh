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

# Auto-create a node in a local panel and write Elytra's config (same-machine install)
CONFIGURE_LOCAL_NODE="${CONFIGURE_LOCAL_NODE:-false}"
PANEL_DIR="${PANEL_DIR:-/var/www/pyrodactyl}"

# Remote panel (separate-machine) auto-configuration via the panel API
PANEL_URL="${PANEL_URL:-}"
PANEL_API_KEY="${PANEL_API_KEY:-}"
PANEL_SCHEME="${PANEL_SCHEME:-http}"

# Optionally create a sample Minecraft server on the new node (best-effort).
# The egg id depends on the panel's seeded eggs (Pyrodactyl's Vanilla egg is 8).
CONFIGURE_MC_SERVER="${CONFIGURE_MC_SERVER:-false}"
CONFIGURE_MC_EGG="${CONFIGURE_MC_EGG:-8}"

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

# When Elytra is installed on the same machine as the panel, create the node and
# write its config automatically (artisan-native, no API key needed) so a local
# install works out of the box. fqdn/scheme are derived from the panel's APP_URL.
setup_local_node() {
  [ "$CONFIGURE_LOCAL_NODE" == true ] || return 0

  if [ ! -f "$PANEL_DIR/artisan" ]; then
    warning "No local panel found at $PANEL_DIR; skipping automatic node setup."
    return 0
  fi

  output "Configuring a local node via the panel.."
  cd "$PANEL_DIR" || return 0

  # Prefer the facts the panel installer saved ($INSTALL_INFO_DIR/panel-info);
  # fall back to parsing the panel's .env if that file isn't present.
  local panel_db app_url scheme node_fqdn
  load_panel_info || true
  panel_db="${MYSQL_DB:-}"
  app_url="${PANEL_URL:-}"
  scheme="${PANEL_SCHEME:-}"

  [ -z "$panel_db" ] && panel_db=$(grep -E '^DB_DATABASE=' .env | head -n1 | cut -d= -f2- | tr -d '"')
  [ -z "$panel_db" ] && panel_db="panel"
  [ -z "$app_url" ] && app_url=$(grep -E '^APP_URL=' .env | head -n1 | cut -d= -f2- | tr -d '"')
  if [ -z "$scheme" ]; then
    scheme="${app_url%%://*}"
    [ "$scheme" == "https" ] || scheme="http"
  fi
  node_fqdn="${app_url#*://}"; node_fqdn="${node_fqdn%%/*}"
  [ -z "$node_fqdn" ] && node_fqdn="$(get_primary_ip)"

  # Detect node resources (MB) with sane fallbacks
  local mem disk
  mem=$(free -m 2>/dev/null | awk '/^Mem:/{print $2}'); [ -z "$mem" ] && mem=4096
  disk=$(df -Pm /var/lib 2>/dev/null | awk 'NR==2{print $2}'); [ -z "$disk" ] && disk=20480

  # Location: short code from the server's country (IP geolocation), falling back to
  # "local". Idempotent.
  local loc_short
  loc_short=$(get_server_country_code)
  if ! mariadb -u root -D "$panel_db" -N -B -e "SELECT id FROM locations WHERE short='$loc_short' LIMIT 1;" 2>/dev/null | grep -q .; then
    php artisan p:location:make --short="$loc_short" --long="$loc_short" -n </dev/null || warning "Could not create location"
  fi
  local location_id
  location_id=$(mariadb -u root -D "$panel_db" -N -B -e "SELECT id FROM locations WHERE short='$loc_short' LIMIT 1;" 2>/dev/null)

  # Node (idempotent)
  if ! mariadb -u root -D "$panel_db" -N -B -e "SELECT id FROM nodes WHERE name='local' LIMIT 1;" 2>/dev/null | grep -q .; then
    php artisan p:node:make \
      --name=local \
      --description="Local node (auto-created by pyrodactyl-installer)" \
      --locationId="$location_id" \
      --fqdn="$node_fqdn" \
      --public=1 \
      --scheme="$scheme" \
      --proxy=no \
      --maxMemory="$mem" --overallocateMemory=0 \
      --maxDisk="$disk" --overallocateDisk=0 \
      --uploadSize=100 -n </dev/null || warning "Could not create node"
  fi
  local node_id
  node_id=$(mariadb -u root -D "$panel_db" -N -B -e "SELECT id FROM nodes WHERE name='local' LIMIT 1;" 2>/dev/null)

  if [ -z "$node_id" ]; then
    warning "Node creation failed; configure the node manually from the panel."
    return 0
  fi
  export NODE_ID="$node_id"

  # Allocations: ports 25500-25600, ip 0.0.0.0
  output "Adding allocations (ports 25500-25600) to node $node_id.."
  local p
  for p in $(seq 25500 25600); do
    mariadb -u root -e "INSERT IGNORE INTO ${panel_db}.allocations (node_id, ip, port) VALUES ($node_id, '0.0.0.0', $p);"
  done

  # Write Elytra's config straight from the panel
  output "Writing /etc/elytra/config.yml from the panel.."
  mkdir -p /etc/elytra
  if php artisan p:node:configuration "$node_id" </dev/null >/etc/elytra/config.yml; then
    success "Elytra configured for node $node_id ($scheme://$node_fqdn)."
    if [ "$scheme" == "http" ]; then
      systemctl restart elytra && success "Elytra started."
    else
      warning "Node uses https; install a TLS certificate for $node_fqdn, then: systemctl start elytra"
    fi
  else
    warning "Could not generate the Elytra config; configure the node manually from the panel."
  fi
}

# When the panel is on a DIFFERENT machine, use its API (app key) to create the
# node, then let `elytra configure` pull the config. fqdn = this machine.
auto_configure_via_api() {
  { [ -n "$PANEL_URL" ] && [ -n "$PANEL_API_KEY" ]; } || return 0

  output "Auto-configuring this node against the panel at $PANEL_URL.."
  command -v jq >/dev/null 2>&1 || install_packages "jq"

  # Node fqdn = this server; scheme http unless an SSL cert/LE is being set up here.
  local node_fqdn scheme mem disk location_id node_id
  node_fqdn="${FQDN:-$(get_primary_ip)}"
  scheme="http"; [ "$CONFIGURE_LETSENCRYPT" == true ] && scheme="https"
  mem=$(free -m 2>/dev/null | awk '/^Mem:/{print $2}'); [ -z "$mem" ] && mem=4096
  disk=$(df -Pm /var/lib 2>/dev/null | awk 'NR==2{print $2}'); [ -z "$disk" ] && disk=20480

  output "Creating location via the panel API.."
  if ! location_id=$(get_or_create_location "$PANEL_API_KEY" "$PANEL_URL" "$(get_server_country_code)"); then
    warning "Could not create a location; configure the node manually from the panel."
    return 0
  fi

  output "Creating node via the panel API.."
  if ! node_id=$(create_node_via_api "$PANEL_API_KEY" "$PANEL_URL" "$location_id" "$(hostname -s)" "$mem" "$disk" "$scheme" "$node_fqdn"); then
    warning "Could not create the node; configure it manually from the panel."
    return 0
  fi
  export NODE_ID="$node_id"

  output "Configuring Elytra (elytra configure).."
  if (cd /etc/elytra && elytra configure --panel-url "$PANEL_URL" --token "$PANEL_API_KEY" --node "$node_id"); then
    success "Elytra configured for node $node_id ($scheme://$node_fqdn)."
  else
    warning "elytra configure failed; use the panel's auto-deploy command to configure manually."
    return 0
  fi

  output "Adding allocations (ports 25500-25600).."
  create_node_allocations "$PANEL_API_KEY" "$PANEL_URL" "$node_id" "0.0.0.0" 25500 25600

  if [ "$scheme" == "http" ]; then
    systemctl restart elytra && success "Elytra started."
  else
    warning "Node uses https; install a TLS certificate for $node_fqdn, then: systemctl start elytra"
  fi
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

  # Node setup: same-machine uses artisan directly; separate-machine uses the panel API.
  if [ "$CONFIGURE_LOCAL_NODE" == true ]; then
    setup_local_node
  else
    auto_configure_via_api
  fi

  # Optional best-effort sample Minecraft server (needs a node + panel API key).
  if [ "$CONFIGURE_MC_SERVER" == true ] && [ -n "${NODE_ID:-}" ] && [ -n "${PANEL_URL:-}" ] && [ -n "${PANEL_API_KEY:-}" ]; then
    create_mc_server "$PANEL_API_KEY" "$PANEL_URL" "$NODE_ID" "$CONFIGURE_MC_EGG"
  fi

  return 0
}

# ---------------- Installation ---------------- #

perform_install
