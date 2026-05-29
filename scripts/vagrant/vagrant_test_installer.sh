#!/bin/bash
#
# Non-interactive driver used by the Vagrantfile to exercise the installer
# scripts end-to-end inside a freshly-provisioned VM. No prompts; everything is
# fed via env vars. For testing the interactive prompts, use
# vagrant_test_interactive.sh instead.
#
# Usage (inside the VM, as root):
#   /vagrant/scripts/vagrant/vagrant_test_installer.sh panel
#   /vagrant/scripts/vagrant/vagrant_test_installer.sh wings
#   /vagrant/scripts/vagrant/vagrant_test_installer.sh both
#
# Env vars you may override before calling (all have sensible defaults):
#   TEST_TARGET              panel | wings | both | none         (default: both)
#   TEST_LOCAL               fetch repo files from /vagrant      (default: true)
#   TEST_FQDN                FQDN/host for the panel             (default: panel.local)
#   TEST_TIMEZONE            PHP timezone string                 (default: Europe/Stockholm)
#   TEST_EMAIL               LE / admin notification email       (default: admin@example.com)
#   TEST_ADMIN_USER          initial admin username              (default: admin)
#   TEST_ADMIN_PASSWORD      initial admin password              (default: Password123!)
#   TEST_MYSQL_DB            panel database name                 (default: panel)
#   TEST_MYSQL_USER          panel database user                 (default: pyrodactyl)
#   TEST_MYSQL_PASSWORD      panel database password             (default: random)
#   TEST_RUSTIC              install rustic during Elytra test   (default: true)
#   TEST_GITHUB_SOURCE       branch/tag the scripts curl from    (default: master)

# NB: no `set -e`. Failures are handled explicitly per phase so that, e.g., a
# panel failure during `both` is reported clearly instead of silently aborting.
set -uo pipefail

TARGET="${1:-${TEST_TARGET:-both}}"

# -------- 0. Make the lib script discoverable --------
# installers/*.sh source /tmp/pyrodactyl-lib.sh; /tmp is wiped on reboot,
# so re-create the symlink unconditionally.
ln -sf /vagrant/lib/lib.sh /tmp/pyrodactyl-lib.sh

# -------- 1. Common env (used by both panel & wings) --------
# By default the installer fetches repo files (configs, lib, verify-fqdn) from the
# local /vagrant checkout via a file:// URL, so you can test un-pushed changes.
# Set TEST_LOCAL=false to fetch from GitHub instead (uses TEST_GITHUB_SOURCE).
TEST_LOCAL="${TEST_LOCAL:-true}"
export GITHUB_BASE_URL="https://raw.githubusercontent.com/Muspelheim-Hosting/pterodactyl-installer"
export GITHUB_SOURCE="${TEST_GITHUB_SOURCE:-master}"
if [ "$TEST_LOCAL" == true ]; then
  export GITHUB_URL="file:///vagrant"
else
  export GITHUB_URL="$GITHUB_BASE_URL/$GITHUB_SOURCE"
fi
echo "==> Fetching repo files from: $GITHUB_URL"

# -------- 2. Panel-specific env --------
export FQDN="${TEST_FQDN:-panel.local}"
export MYSQL_DB="${TEST_MYSQL_DB:-panel}"
export MYSQL_USER="${TEST_MYSQL_USER:-pyrodactyl}"
# `head` closing the pipe gives `tr` a SIGPIPE; isolate it from pipefail so the
# script doesn't abort on the (expected) non-zero pipeline status.
export MYSQL_PASSWORD="${TEST_MYSQL_PASSWORD:-$(set +o pipefail; tr -dc 'A-Za-z0-9' </dev/urandom | head -c 32)}"
export timezone="${TEST_TIMEZONE:-Europe/Stockholm}"
export email="${TEST_EMAIL:-admin@example.com}"
export user_email="${TEST_EMAIL:-admin@example.com}"
export user_username="${TEST_ADMIN_USER:-admin}"
export user_firstname="Admin"
export user_lastname="User"
export user_password="${TEST_ADMIN_PASSWORD:-Password123!}"

# No interactive prompts, no Let's Encrypt (the VM isn't internet-reachable),
# no firewall (keep the test fast and avoid locking ourselves out of SSH).
export ASSUME_SSL=false
export CONFIGURE_LETSENCRYPT=false
export CONFIGURE_FIREWALL=false
export CONFIGURE_UFW=false
export CONFIGURE_FIREWALL_CMD=false

# -------- 3. Wings/Elytra-specific env --------
export INSTALL_MARIADB=false
export CONFIGURE_DBHOST=false
export CONFIGURE_DB_FIREWALL=false
export CONFIGURE_RUSTIC="${TEST_RUSTIC:-true}"
# For `both`, auto-create the local node + Elytra config (out-of-box single-machine).
export CONFIGURE_LOCAL_NODE="${TEST_LOCAL_NODE:-true}"

run_phase() {
  local label="$1" script="$2"
  echo ""
  echo "==> [$label] START ($script)"
  if bash "$script"; then
    echo "==> [$label] OK"
    return 0
  fi
  local rc=$?
  echo "==> [$label] FAILED (exit $rc)" >&2
  return "$rc"
}

case "$TARGET" in
  panel) run_phase panel /vagrant/installers/panel.sh ;;
  wings) run_phase wings /vagrant/installers/wings.sh ;;
  both)
    # Run panel, then Elytra. If panel fails, stop and say so (don't pretend both ran).
    if ! run_phase panel /vagrant/installers/panel.sh; then
      echo "==> Panel phase failed; skipping Elytra. Fix the panel install first." >&2
      exit 1
    fi
    run_phase wings /vagrant/installers/wings.sh
    ;;
  none)  echo "==> TEST_TARGET=none, skipping install"; exit 0 ;;
  *)
    echo "Unknown target: $TARGET (expected: panel | wings | both | none)" >&2
    exit 2
    ;;
esac

rc=$?
[ "$rc" -eq 0 ] && echo "==> Done." || echo "==> Finished with errors (exit $rc)." >&2
exit "$rc"
