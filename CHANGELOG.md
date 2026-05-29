# Changelog

This project follows the [semantic versioning](https://semver.org) convention. Changelog points should be divided into fixed, changed, or added.

## v1.0.0 - Initial Pyrodactyl/Elytra fork

### Changed

- Forked [pterodactyl-installer](https://github.com/pterodactyl-installer/pterodactyl-installer) and rebranded to `pyrodactyl-installer`.
- Panel now installs [Pyrodactyl](https://github.com/pyrodactyl-oss/pyrodactyl) (`pyrodactyl-oss/pyrodactyl`) instead of Pterodactyl Panel.
- Daemon now installs [Elytra](https://github.com/pyrohost/elytra) (`pyrohost/elytra`) instead of Wings. Binary at `/usr/local/bin/elytra`, config at `/etc/elytra`, data at `/var/lib/elytra`.
- Bumped PHP from 8.3 to **8.4** (Pyrodactyl's `composer.lock` requires PHP >= 8.4). Added `intl` and `redis` PHP extensions.
- Added a frontend build step: the panel installer now installs Node.js 20 + pnpm and runs `pnpm install && pnpm build`, because Pyrodactyl's release tarball ships an unbuilt React/Vite frontend (Pterodactyl shipped prebuilt assets).
- The panel installer fetches `.env.example` from the Pyrodactyl repository when it is absent from the release tarball.
- Elytra installer: pre-creates the `pyrodactyl` system user (avoids Elytra's "failed to create pyrodactyl system user error=exit status 4" start failure), installs the Docker buildx/compose plugins, and optionally installs [rustic](https://github.com/rustic-rs/rustic) for deduplicated, encrypted backups (prompted; `CONFIGURE_RUSTIC`, default on).
- Renamed systemd units: `pteroq.service` → `pyroq.service`, `wings.service` → `elytra.service`.
- Renamed paths: panel web root `/var/www/pterodactyl` → `/var/www/pyrodactyl`; php-fpm pool `www-pterodactyl.conf` → `www-pyrodactyl.conf`; nginx vhost/socket `pterodactyl.*` → `pyrodactyl.*`.
- Default panel database user `pterodactyl` → `pyrodactyl`; database host user `pterodactyluser` → `pyrodactyluser`.
- Install log path `/var/log/pterodactyl-installer.log` → `/var/log/pyrodactyl-installer.log`.
- FQDN verification now uses the public `api.ipify.org` check-IP service.

### Added

- **Local / no-SSL install:** the panel UI asks about SSL first; if declined it skips the FQDN entirely and serves over `http://<auto-detected-IP>` so a local install works out of the box. When SSL is wanted the FQDN is validated instantly (format) and via DNS before continuing.
- **Single shared menu:** the installer menu lives once in `lib/lib.sh` (`main_menu`), used by both `install.sh` and the interactive Vagrant test driver.
- **Detailed end-of-install summary:** panel/Elytra print URL, login, DB, paths, live service status, the generated API key, and next steps.
- **Panel → Elytra handoff:** the panel installer generates an application API key and writes `/var/lib/pyrodactyl-installer/panel-info` (mode 0600); the Elytra installer reads it.
- **Same-machine auto node setup:** when a local panel is detected, the Elytra installer auto-creates the location/node/allocations (artisan-native) and writes `/etc/elytra/config.yml`, then starts Elytra over HTTP.
- **Separate-machine fast-track:** the Elytra installer can take a panel URL + API key and create the node over the panel REST API, then run `elytra configure`.
- **Location by geolocation:** the node's panel location short code is derived from the server's country (ipapi.co → ipinfo.io → ifconfig.co), falling back to `local`.
- **Optional phpMyAdmin** (Debian/Ubuntu) served on port 8081.
- **Optional sample Minecraft server** created via the panel API after node setup (best-effort; `CONFIGURE_MC_SERVER`, egg id `CONFIGURE_MC_EGG`).
- Ensures the `php` CLI resolves to 8.4 even when multiple PHP versions are installed.
- Vagrant: an interactive end-to-end test driver (`scripts/vagrant/vagrant_test_interactive.sh`) plus `test`/`test-interactive` provisioners.