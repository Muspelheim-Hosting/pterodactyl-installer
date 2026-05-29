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

export GITHUB_SOURCE="v1.0.0"
export SCRIPT_RELEASE="v1.0.0"
export GITHUB_BASE_URL="https://raw.githubusercontent.com/Muspelheim-Hosting/pterodactyl-installer"

# shellcheck disable=SC2034  # consumed by lib/lib.sh (execute/main_menu) after sourcing
export LOG_PATH="/var/log/pyrodactyl-installer.log"

# check for curl
if ! [ -x "$(command -v curl)" ]; then
  echo "* curl is required in order for this script to work."
  echo "* install using apt (Debian and derivatives) or yum/dnf (CentOS)"
  exit 1
fi

# Always remove lib.sh, before downloading it
[ -f /tmp/pyrodactyl-lib.sh ] && rm -rf /tmp/pyrodactyl-lib.sh
curl -sSL -o /tmp/pyrodactyl-lib.sh "$GITHUB_BASE_URL"/master/lib/lib.sh
# shellcheck source=lib/lib.sh
source /tmp/pyrodactyl-lib.sh

welcome ""

# The menu (and the execute/run logic) lives in lib/lib.sh so install.sh and the
# interactive Vagrant test driver share a single definition.
main_menu

# Remove lib.sh, so next time the script is run the, newest version is downloaded.
rm -rf /tmp/pyrodactyl-lib.sh
