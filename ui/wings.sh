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

# Install mariadb
export INSTALL_MARIADB=false

# Firewall
export CONFIGURE_FIREWALL=false

# SSL (Let's Encrypt)
export CONFIGURE_LETSENCRYPT=false
export FQDN=""
export EMAIL=""

# Rustic backup tool (deduplicated, encrypted backups)
export CONFIGURE_RUSTIC=true

# Auto-create a node + write Elytra config when a local panel is detected
export CONFIGURE_LOCAL_NODE=false

# Remote panel auto-configuration (separate-machine install)
export PANEL_URL=""
export PANEL_API_KEY=""

# Optionally create a sample Minecraft server on the new node (best-effort)
export CONFIGURE_MC_SERVER=false

# Database host
export CONFIGURE_DBHOST=false
export CONFIGURE_DB_FIREWALL=false
export MYSQL_DBHOST_HOST="127.0.0.1"
export MYSQL_DBHOST_USER="pyrodactyluser"
export MYSQL_DBHOST_PASSWORD=""

# ------------ User input functions ------------ #

ask_letsencrypt() {
  if [ "$CONFIGURE_UFW" == false ] && [ "$CONFIGURE_FIREWALL_CMD" == false ]; then
    warning "Let's Encrypt requires port 80/443 to be opened! You have opted out of the automatic firewall configuration; use this at your own risk (if port 80/443 is closed, the script will fail)!"
  fi

  warning "You cannot use Let's Encrypt with your hostname as an IP address! It must be a FQDN (e.g. node.example.org)."

  echo -e -n "* Do you want to automatically configure HTTPS using Let's Encrypt? (y/N): "
  read -r CONFIRM_SSL

  if [[ "$CONFIRM_SSL" =~ [Yy] ]]; then
    CONFIGURE_LETSENCRYPT=true
  fi
}

ask_database_user() {
  echo -n "* Do you want to automatically configure a user for database hosts? (y/N): "
  read -r CONFIRM_DBHOST

  if [[ "$CONFIRM_DBHOST" =~ [Yy] ]]; then
    ask_database_external
    CONFIGURE_DBHOST=true
  fi
}

ask_database_external() {
  echo -n "* Do you want to configure MySQL to be accessed externally? (y/N): "
  read -r CONFIRM_DBEXTERNAL

  if [[ "$CONFIRM_DBEXTERNAL" =~ [Yy] ]]; then
    echo -n "* Enter the panel address (blank for any address): "
    read -r CONFIRM_DBEXTERNAL_HOST
    if [ "$CONFIRM_DBEXTERNAL_HOST" == "" ]; then
      MYSQL_DBHOST_HOST="%"
    else
      MYSQL_DBHOST_HOST="$CONFIRM_DBEXTERNAL_HOST"
    fi
    [ "$CONFIGURE_FIREWALL" == true ] && ask_database_firewall
    return 0
  fi
}

ask_database_firewall() {
  warning "Allow incoming traffic to port 3306 (MySQL) can potentially be a security risk, unless you know what you are doing!"
  echo -n "* Would you like to allow incoming traffic to port 3306? (y/N): "
  read -r CONFIRM_DB_FIREWALL
  if [[ "$CONFIRM_DB_FIREWALL" =~ [Yy] ]]; then
    CONFIGURE_DB_FIREWALL=true
  fi
}

ask_rustic() {
  output "Rustic enables deduplicated, encrypted backups for Elytra. It is optional but recommended."
  echo -e -n "* Do you want to install rustic? (Y/n): "
  read -r CONFIRM_RUSTIC

  [[ "$CONFIRM_RUSTIC" =~ [Nn] ]] && CONFIGURE_RUSTIC=false
  true
}

ask_local_node() {
  # Only relevant when the panel is on this same machine.
  [ -d "/var/www/pyrodactyl" ] || return 0

  output "A local Pyrodactyl panel was detected on this machine."
  output "The installer can create a node for it and configure Elytra automatically,"
  output "so a single-machine install works out of the box (recommended)."
  echo -e -n "* Automatically create a local node and configure Elytra? (Y/n): "
  read -r CONFIRM_LOCAL_NODE

  [[ "$CONFIRM_LOCAL_NODE" =~ [Nn] ]] || CONFIGURE_LOCAL_NODE=true
  true
}

ask_remote_panel() {
  # Only relevant when the panel is on a different machine.
  [ -d "/var/www/pyrodactyl" ] && return 0

  output "If your Pyrodactyl panel is on another machine, this node can be configured"
  output "automatically using the panel URL and an application API key (the panel"
  output "installer prints/saves one)."
  echo -e -n "* Auto-configure this node from a remote panel now? (y/N): "
  read -r CONFIRM_REMOTE
  [[ "$CONFIRM_REMOTE" =~ [Yy] ]] || return 0

  while [ -z "$PANEL_URL" ]; do
    echo -n "* Panel URL (e.g. https://panel.example.com): "
    read -r PANEL_URL
  done
  while [ -z "$PANEL_API_KEY" ]; do
    echo -n "* Panel application API key (pyro_...): "
    read -r PANEL_API_KEY
  done
  export PANEL_URL PANEL_API_KEY
}

ask_mc_server() {
  # Only meaningful if a node will actually be set up (local or remote).
  { [ "$CONFIGURE_LOCAL_NODE" == true ] || [ -n "$PANEL_API_KEY" ]; } || return 0

  output "Optionally create a sample Minecraft server on the new node (best-effort)."
  echo -e -n "* Create a sample Minecraft server? (y/N): "
  read -r CONFIRM_MC

  [[ "$CONFIRM_MC" =~ [Yy] ]] && CONFIGURE_MC_SERVER=true
  true
}

####################
## MAIN FUNCTIONS ##
####################

main() {
  # check if we can detect an already existing installation
  if [ -d "/etc/elytra" ]; then
    warning "The script has detected that you already have Pyrodactyl Elytra on your system! You cannot run the script multiple times, it will fail!"
    echo -e -n "* Are you sure you want to proceed? (y/N): "
    read -r CONFIRM_PROCEED
    if [[ ! "$CONFIRM_PROCEED" =~ [Yy] ]]; then
      error "Installation aborted!"
      exit 1
    fi
  fi

  welcome "wings"

  check_virt

  echo "* "
  echo "* The installer will install Docker, required dependencies for Elytra"
  echo "* as well as Elytra itself. But it's still required to create the node"
  echo "* on the panel and then place the configuration file on the node manually after"
  echo "* the installation has finished. Read more about this process on the"
  echo "* official documentation: $(hyperlink 'https://github.com/pyrohost/elytra#readme')"
  echo "* "
  echo -e "* ${COLOR_RED}Note${COLOR_NC}: this script will not start Elytra automatically (will install systemd service, not start it)."
  echo -e "* ${COLOR_RED}Note${COLOR_NC}: this script will not enable swap (for docker)."
  print_brake 42

  ask_firewall CONFIGURE_FIREWALL

  ask_rustic

  ask_local_node
  ask_remote_panel
  ask_mc_server

  ask_database_user

  if [ "$CONFIGURE_DBHOST" == true ]; then
    type mysql >/dev/null 2>&1 && HAS_MYSQL=true || HAS_MYSQL=false

    if [ "$HAS_MYSQL" == false ]; then
      INSTALL_MARIADB=true
    fi

    MYSQL_DBHOST_USER="-"
    while [[ "$MYSQL_DBHOST_USER" == *"-"* ]]; do
      required_input MYSQL_DBHOST_USER "Database host username (pyrodactyluser): " "" "pyrodactyluser"
      [[ "$MYSQL_DBHOST_USER" == *"-"* ]] && error "Database user cannot contain hyphens"
    done

    password_input MYSQL_DBHOST_PASSWORD "Database host password: " "Password cannot be empty"
  fi

  ask_letsencrypt

  if [ "$CONFIGURE_LETSENCRYPT" == true ]; then
    while [ -z "$FQDN" ]; do
      echo -n "* Set the FQDN to use for Let's Encrypt (node.example.com): "
      read -r FQDN

      ASK=false

      [ -z "$FQDN" ] && error "FQDN cannot be empty"                                                            # check if FQDN is empty
      [ -n "$FQDN" ] && ! valid_fqdn "$FQDN" && error "Invalid FQDN. Use a domain name, not an IP address." && FQDN="" && ASK=true # instant format check
      [ -n "$FQDN" ] && { bash <(curl -s "$GITHUB_URL"/lib/verify-fqdn.sh) "$FQDN" || ASK=true; }               # check if FQDN resolves
      [ -d "/etc/letsencrypt/live/$FQDN/" ] && error "A certificate with this FQDN already exists!" && ASK=true # check if cert exists

      [ "$ASK" == true ] && FQDN=""
      [ "$ASK" == true ] && echo -e -n "* Do you still want to automatically configure HTTPS using Let's Encrypt? (y/N): "
      [ "$ASK" == true ] && read -r CONFIRM_SSL

      if [[ ! "$CONFIRM_SSL" =~ [Yy] ]] && [ "$ASK" == true ]; then
        CONFIGURE_LETSENCRYPT=false
        FQDN=""
      fi
    done
  fi

  if [ "$CONFIGURE_LETSENCRYPT" == true ]; then
    # set EMAIL
    while ! valid_email "$EMAIL"; do
      echo -n "* Enter email address for Let's Encrypt: "
      read -r EMAIL

      valid_email "$EMAIL" || error "Email cannot be empty or invalid"
    done
  fi

  echo -n "* Proceed with installation? (y/N): "

  read -r CONFIRM
  if [[ "$CONFIRM" =~ [Yy] ]]; then
    run_installer "wings"
  else
    error "Installation aborted."
    exit 1
  fi
}

function goodbye {
  echo ""
  print_brake 70
  output "Elytra installation completed!"
  output ""
  output "Binary:        /usr/local/bin/elytra"
  output "Config:        /etc/elytra/config.yml"
  output "Data:          /var/lib/elytra"
  output "rustic:        $([ -x /usr/local/bin/rustic ] && echo "/usr/local/bin/rustic (backups enabled)" || echo "not installed")"
  output ""
  output "Service status:"
  output "  docker:  $(systemctl is-active docker 2>/dev/null || true)"
  output "  elytra:  $(systemctl is-active elytra 2>/dev/null || true)  (not started yet — needs a config)"
  output ""
  output "To finish, attach this node to your panel:"
  output "  1. In the panel: Admin -> Nodes -> Create, then open the node's Configuration tab."
  output "  2. Click \"Generate Token\" / auto-deploy and paste its command here, e.g.:"
  output "       cd /etc/elytra && sudo elytra configure --panel-url <url> --token <token> --node <id>"
  output "  3. Verify it runs:  sudo elytra"
  output "  4. Then start the service:  systemctl enable --now elytra"
  output ""
  output "Docs: $(hyperlink 'https://github.com/pyrohost/elytra#readme')"
  echo -e "* ${COLOR_RED}Note${COLOR_NC}: It is recommended to enable swap for Docker."
  [ "$CONFIGURE_FIREWALL" == false ] && echo -e "* ${COLOR_RED}Note${COLOR_NC}: If you haven't configured your firewall, ports 8080 and 2022 must be open."
  print_brake 70
  echo ""
}

# run script
main
goodbye
