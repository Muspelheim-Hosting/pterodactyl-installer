#!/bin/bash
#
# Interactive end-to-end test driver. Boots the SAME menu as install.sh (defined
# once in lib/lib.sh as `main_menu`), so you exercise every prompt, the FQDN/SSL/
# firewall logic, the summary and the final confirm -> install -- all reading lib,
# ui, installers and configs from the LOCAL /vagrant checkout (no GitHub round
# trip), so un-pushed changes are tested.
#
# Usage (inside the VM, with a real terminal):
#   sudo /vagrant/scripts/vagrant/vagrant_test_interactive.sh
#
# Env vars:
#   TEST_LOCAL          read lib/ui/installers/configs from /vagrant (default: true)
#   TEST_GITHUB_SOURCE  branch/tag to fetch from when TEST_LOCAL=false (default: master)

# Match install.sh's shell options (lib/ui/installers assume `set -e`, not `set -u`).
set -e

if [[ $EUID -ne 0 ]]; then
  echo "* This script must be run as root (sudo)." >&2
  exit 1
fi

# -------- Make the shared lib discoverable (installers/ui source it) --------
ln -sf /vagrant/lib/lib.sh /tmp/pyrodactyl-lib.sh

# -------- Read lib + ui + installers + configs locally by default --------
TEST_LOCAL="${TEST_LOCAL:-true}"
export GITHUB_BASE_URL="https://raw.githubusercontent.com/Muspelheim-Hosting/pterodactyl-installer"
export GITHUB_SOURCE="${TEST_GITHUB_SOURCE:-master}"
if [ "$TEST_LOCAL" == true ]; then
  export GITHUB_URL="file:///vagrant"
else
  export GITHUB_URL="$GITHUB_BASE_URL/$GITHUB_SOURCE"
fi
echo "==> lib, UI, installers and configs will be read from: $GITHUB_URL"

# Source the shared library (defines welcome + main_menu, the same entrypoint
# install.sh uses). update_lib_source is a no-op for a file:// GITHUB_URL.
# shellcheck source=/dev/null
source /tmp/pyrodactyl-lib.sh

welcome ""
main_menu

echo ""
echo "==> Done."
