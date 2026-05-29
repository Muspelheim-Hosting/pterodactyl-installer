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