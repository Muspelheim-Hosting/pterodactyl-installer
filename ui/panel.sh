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

# Domain name / IP
export FQDN=""

# Default MySQL credentials
export MYSQL_DB=""
export MYSQL_USER=""
export MYSQL_PASSWORD=""

# Environment
export timezone=""
export email=""

# Initial admin account
export user_email=""
export user_username=""
export user_firstname=""
export user_lastname=""
export user_password=""

# Assume SSL, will fetch different config if true
export ASSUME_SSL=false
export CONFIGURE_LETSENCRYPT=false

# Firewall
export CONFIGURE_FIREWALL=false

# phpMyAdmin (Debian/Ubuntu only)
export CONFIGURE_PHPMYADMIN=false

# ------------ User input functions ------------ #

ask_phpmyadmin() {
  # apt-only feature
  case "$OS" in
  ubuntu | debian) ;;
  *) return 0 ;;
  esac

  output "phpMyAdmin gives a web UI for the database (served on port 8081)."
  echo -e -n "* Do you want to install phpMyAdmin? (y/N): "
  read -r CONFIRM_PMA

  [[ "$CONFIRM_PMA" =~ [Yy] ]] && CONFIGURE_PHPMYADMIN=true
  true
}

ask_letsencrypt() {
  if [ "$CONFIGURE_UFW" == false ] && [ "$CONFIGURE_FIREWALL_CMD" == false ]; then
    warning "Let's Encrypt requires port 80/443 to be opened! You have opted out of the automatic firewall configuration; use this at your own risk (if port 80/443 is closed, the script will fail)!"
  fi

  echo -e -n "* Do you want to automatically configure HTTPS using Let's Encrypt? (y/N): "
  read -r CONFIRM_SSL

  if [[ "$CONFIRM_SSL" =~ [Yy] ]]; then
    CONFIGURE_LETSENCRYPT=true
    ASSUME_SSL=false
  fi
}

ask_assume_ssl() {
  output "Let's Encrypt is not going to be automatically configured by this script (user opted out)."
  output "You can 'assume' Let's Encrypt, which means the script will download a nginx configuration that is configured to use a Let's Encrypt certificate but the script won't obtain the certificate for you."
  output "If you assume SSL and do not obtain the certificate, your installation will not work."
  echo -n "* Assume SSL or not? (y/N): "
  read -r ASSUME_SSL_INPUT

  [[ "$ASSUME_SSL_INPUT" =~ [Yy] ]] && ASSUME_SSL=true
  true
}

# SSL is the only reason an FQDN is needed. If the user doesn't want SSL we skip
# the FQDN entirely and serve the panel over plain HTTP on the server's IP. If
# they do want SSL we demand a valid domain and validate it before continuing.
ask_ssl_and_fqdn() {
  output "SSL/HTTPS requires a domain name (FQDN) that points at this server."
  output "Without SSL the panel is served over plain HTTP using this server's IP address."
  echo -e -n "* Do you want to configure SSL (HTTPS)? (y/N): "
  read -r WANT_SSL

  if [[ ! "$WANT_SSL" =~ [Yy] ]]; then
    FQDN="$(get_primary_ip)"
    ASSUME_SSL=false
    CONFIGURE_LETSENCRYPT=false
    output "No SSL selected. The panel will be served over http://$FQDN"
    return 0
  fi

  # SSL wanted: require a valid domain, validated instantly (format) before continuing.
  FQDN=""
  while [ -z "$FQDN" ]; do
    echo -n "* Set the FQDN of this panel (panel.example.com): "
    read -r FQDN
    if ! valid_fqdn "$FQDN"; then
      error "Invalid FQDN. Use a domain name (e.g. panel.example.com), not an IP address."
      FQDN=""
    fi
  done

  # Let's Encrypt (auto-obtain) or assume an externally-provided certificate.
  ask_letsencrypt
  [ "$CONFIGURE_LETSENCRYPT" == false ] && ask_assume_ssl

  # Validate the FQDN's DNS now, before installing (matches the upstream behaviour).
  bash <(curl -s "$GITHUB_URL"/lib/verify-fqdn.sh) "$FQDN"
}

main() {
  # check if we can detect an already existing installation
  if [ -d "/var/www/pyrodactyl" ]; then
    warning "The script has detected that you already have Pyrodactyl panel on your system! You cannot run the script multiple times, it will fail!"
    echo -e -n "* Are you sure you want to proceed? (y/N): "
    read -r CONFIRM_PROCEED
    if [[ ! "$CONFIRM_PROCEED" =~ [Yy] ]]; then
      error "Installation aborted!"
      exit 1
    fi
  fi

  welcome "panel"

  check_os_x86_64

  # set database credentials
  output "Database configuration."
  output ""
  output "This will be the credentials used for communication between the MySQL"
  output "database and the panel. You do not need to create the database"
  output "before running this script, the script will do that for you."
  output ""

  MYSQL_DB="-"
  while [[ "$MYSQL_DB" == *"-"* ]]; do
    required_input MYSQL_DB "Database name (panel): " "" "panel"
    [[ "$MYSQL_DB" == *"-"* ]] && error "Database name cannot contain hyphens"
  done

  MYSQL_USER="-"
  while [[ "$MYSQL_USER" == *"-"* ]]; do
    required_input MYSQL_USER "Database username (pyrodactyl): " "" "pyrodactyl"
    [[ "$MYSQL_USER" == *"-"* ]] && error "Database user cannot contain hyphens"
  done

  # MySQL password input
  rand_pw=$(gen_passwd 64)
  password_input MYSQL_PASSWORD "Password (press enter to use randomly generated password): " "MySQL password cannot be empty" "$rand_pw"

  readarray -t valid_timezones <<<"$(curl -s "$GITHUB_URL"/configs/valid_timezones.txt)"
  output "List of valid timezones here $(hyperlink "https://www.php.net/manual/en/timezones.php")"

  while [ -z "$timezone" ]; do
    echo -n "* Select timezone [Europe/Stockholm]: "
    read -r timezone_input

    array_contains_element "$timezone_input" "${valid_timezones[@]}" && timezone="$timezone_input"
    [ -z "$timezone_input" ] && timezone="Europe/Stockholm" # because köttbullar!
  done

  email_input email "Provide the email address for Pyrodactyl (also used for Let's Encrypt if SSL is enabled): " "Email cannot be empty or invalid"

  # Initial admin account
  email_input user_email "Email address for the initial admin account: " "Email cannot be empty or invalid"
  required_input user_username "Username for the initial admin account: " "Username cannot be empty"
  required_input user_firstname "First name for the initial admin account: " "Name cannot be empty"
  required_input user_lastname "Last name for the initial admin account: " "Name cannot be empty"
  password_input user_password "Password for the initial admin account: " "Password cannot be empty"

  print_brake 72

  # Ask if firewall is needed
  ask_firewall CONFIGURE_FIREWALL

  # Optional phpMyAdmin
  ask_phpmyadmin

  # SSL decision + FQDN (FQDN is only needed when SSL is wanted)
  ask_ssl_and_fqdn

  # summary
  summary

  # confirm installation
  echo -e -n "\n* Initial configuration completed. Continue with installation? (y/N): "
  read -r CONFIRM
  if [[ "$CONFIRM" =~ [Yy] ]]; then
    run_installer "panel"
  else
    error "Installation aborted."
    exit 1
  fi
}

summary() {
  print_brake 62
  output "Pyrodactyl panel $PYRODACTYL_PANEL_VERSION with nginx on $OS"
  output "Database name: $MYSQL_DB"
  output "Database user: $MYSQL_USER"
  output "Database password: (censored)"
  output "Timezone: $timezone"
  output "Email: $email"
  output "User email: $user_email"
  output "Username: $user_username"
  output "First name: $user_firstname"
  output "Last name: $user_lastname"
  output "User password: (censored)"
  output "Hostname/FQDN: $FQDN"
  output "Configure Firewall? $CONFIGURE_FIREWALL"
  output "Install phpMyAdmin? $CONFIGURE_PHPMYADMIN"
  output "Configure Let's Encrypt? $CONFIGURE_LETSENCRYPT"
  output "Assume SSL? $ASSUME_SSL"
  print_brake 62
}

goodbye() {
  local scheme="http"
  { [ "$CONFIGURE_LETSENCRYPT" == true ] || [ "$ASSUME_SSL" == true ]; } && scheme="https"
  local url="$scheme://$FQDN"

  print_brake 70
  output "Pyrodactyl panel installation completed!"
  output ""
  output "Panel URL:     $(hyperlink "$url")"
  output "Admin login:   $user_username  ($user_email)"
  output "Database:      $MYSQL_DB  (user: $MYSQL_USER)  on 127.0.0.1:3306"
  output "DB password:   stored in /var/www/pyrodactyl/.env (DB_PASSWORD)"
  output "Install path:  /var/www/pyrodactyl"
  output "Webserver:     nginx on $OS"
  [ "$CONFIGURE_PHPMYADMIN" == true ] && output "phpMyAdmin:    http://$FQDN:8081  (log in with your MySQL credentials)"
  output "Install log:   $LOG_PATH"

  # Surface the application API key the installer generated (saved for Elytra).
  load_panel_info 2>/dev/null || true
  if [ -n "${PANEL_API_KEY:-}" ]; then
    output ""
    output "Application API key (for adding nodes / the Elytra installer):"
    output "  $PANEL_API_KEY"
    output "  (also saved, root-only, in $INSTALL_INFO_DIR/panel-info)"
  fi
  output ""
  output "Service status:"
  output "  nginx:  $(systemctl is-active nginx 2>/dev/null || true)"
  output "  pyroq:  $(systemctl is-active pyroq 2>/dev/null || true)"
  output "  redis:  $(systemctl is-active redis-server 2>/dev/null || systemctl is-active redis 2>/dev/null || true)"
  output "  mariadb: $(systemctl is-active mariadb 2>/dev/null || true)"
  output ""

  if [ "$ASSUME_SSL" == true ] && [ "$CONFIGURE_LETSENCRYPT" == false ]; then
    warning "You opted to assume SSL but no certificate was obtained. The panel will not load until a cert exists at /etc/ssl/$FQDN.pem / .key."
  fi
  [ "$CONFIGURE_FIREWALL" == false ] && echo -e "* ${COLOR_RED}Note${COLOR_NC}: If you haven't configured the firewall, ports 80/443 (HTTP/HTTPS) must be open."
  output "Next: log in at $(hyperlink "$url") and add a node (Admin -> Nodes) to attach Elytra."
  output "Thank you for using this script."
  print_brake 70
}

# run script
main
goodbye
