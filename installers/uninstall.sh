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

RM_PANEL="${RM_PANEL:-true}"
RM_WINGS="${RM_WINGS:-true}"

# ---------- Uninstallation functions ---------- #

rm_panel_files() {
  output "Removing panel files..."
  rm -rf /var/www/pyrodactyl /usr/local/bin/composer
  [ "$OS" != "centos" ] && [ -L /etc/nginx/sites-enabled/pyrodactyl.conf ] && unlink /etc/nginx/sites-enabled/pyrodactyl.conf
  [ "$OS" != "centos" ] && [ -f /etc/nginx/sites-available/pyrodactyl.conf ] && rm -f /etc/nginx/sites-available/pyrodactyl.conf
  [ "$OS" != "centos" ] && [ ! -L /etc/nginx/sites-enabled/default ] && [ -f /etc/nginx/sites-available/default ] && ln -s /etc/nginx/sites-available/default /etc/nginx/sites-enabled/default
  [ "$OS" == "centos" ] && [ -f /etc/nginx/conf.d/pyrodactyl.conf ] && rm -f /etc/nginx/conf.d/pyrodactyl.conf
  systemctl restart nginx
  success "Removed panel files."
}

rm_docker_containers() {
  output "Removing docker containers and images..."

  docker system prune -a -f

  success "Removed docker containers and images."
}

rm_wings_files() {
  output "Removing Elytra files..."

  systemctl disable --now elytra
  [ -f /etc/systemd/system/elytra.service ] && rm -rf /etc/systemd/system/elytra.service

  [ -d /etc/elytra ] && rm -rf /etc/elytra
  [ -f /usr/local/bin/elytra ] && rm -rf /usr/local/bin/elytra
  [ -d /var/lib/elytra ] && rm -rf /var/lib/elytra
  success "Removed Elytra files."
}

rm_services() {
  output "Removing services..."
  systemctl disable --now pyroq
  rm -rf /etc/systemd/system/pyroq.service
  case "$OS" in
  debian | ubuntu)
    systemctl disable --now redis-server
    ;;
  centos)
    systemctl disable --now redis
    systemctl disable --now php-fpm
    rm -rf /etc/php-fpm.d/www-pyrodactyl.conf
    ;;
  esac
  success "Removed services."
}

rm_cron() {
  output "Removing cron jobs..."
  crontab -l | grep -vF "* * * * * php /var/www/pyrodactyl/artisan schedule:run >> /dev/null 2>&1" | crontab -
  success "Removed cron jobs."
}

rm_database() {
  output "Removing database..."
  valid_db=$(mariadb -u root -e "SELECT schema_name FROM information_schema.schemata;" 2>/dev/null | grep -v -E -- 'schema_name|information_schema|performance_schema|mysql')
  if [[ -z "$valid_db" ]]; then
    warning "No valid databases found."
    return
  fi

  warning "Be careful! This database will be deleted!"
  if [[ "$valid_db" == *"panel"* ]]; then
    echo -n "* Database called panel has been detected. Is it the pyrodactyl database? (y/N): "
    read -r is_panel
    if [[ "$is_panel" =~ [Yy] ]]; then
      DATABASE=panel
    else
      print_list "$valid_db"
    fi
  else
    print_list "$valid_db"
  fi

  while [ -z "$DATABASE" ] || [[ "$valid_db" != *"$DATABASE"* ]]; do
    echo -n "* Choose the panel database (to skip don't input anything): "
    read -r database_input
    if [[ -n "$database_input" ]]; then
      if [[ "$valid_db" == *"$database_input"* ]]; then
        DATABASE="$database_input"
      else
        warning "Invalid database name. Try again."
      fi
    else
      break
    fi
  done

  if [[ -n "$DATABASE" ]]; then
    mariadb -u root -e "DROP DATABASE $DATABASE;" 2>/dev/null || warning "Failed to drop database $DATABASE."
  else
    output "No database selected, skipping removal."
  fi

  # Exclude usernames User and root (Hope no one uses username User)
  output "Removing database user..."
  valid_users=$(mariadb -u root -e "SELECT user FROM mysql.user;" 2>/dev/null | grep -v -E -- 'user|root')
  if [[ -z "$valid_users" ]]; then
    warning "No valid database users found."
    return
  fi

  warning "Be careful! This user will be deleted!"
  if [[ "$valid_users" == *"pyrodactyl"* ]]; then
    echo -n "* User called pyrodactyl has been detected. Is it the pyrodactyl user? (y/N): "
    read -r is_user
    if [[ "$is_user" =~ [Yy] ]]; then
      DB_USER=pyrodactyl
    else
      print_list "$valid_users"
    fi
  else
    print_list "$valid_users"
  fi

  while [ -z "$DB_USER" ] || [[ "$valid_users" != *"$DB_USER"* ]]; do
    echo -n "* Choose the panel user (to skip don't input anything): "
    read -r user_input
    if [[ -n "$user_input" ]]; then
      if [[ "$valid_users" == *"$user_input"* ]]; then
        DB_USER=$user_input
      else
        warning "Invalid username. Try again."
      fi
    else
      break
    fi
  done

  if [[ -n "$DB_USER" ]]; then
    mariadb -u root -e "DROP USER '$DB_USER'@'127.0.0.1';" 2>/dev/null || warning "Failed to drop user $DB_USER."
  else
    output "No user selected, skipping removal."
  fi

  mariadb -u root -e "FLUSH PRIVILEGES;" 2>/dev/null
  success "Removed database and database user (if selected)."
}


# --------------- Main functions --------------- #

perform_uninstall() {
  [ "$RM_PANEL" == true ] && rm_panel_files
  [ "$RM_PANEL" == true ] && rm_cron
  [ "$RM_PANEL" == true ] && rm_database
  [ "$RM_PANEL" == true ] && rm_services
  [ "$RM_WINGS" == true ] && rm_docker_containers
  [ "$RM_WINGS" == true ] && rm_wings_files

  return 0
}

# ------------------ Uninstall ----------------- #

perform_uninstall
