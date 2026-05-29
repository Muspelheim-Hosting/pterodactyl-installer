# :bird: pyrodactyl-installer

[![Shellcheck](https://github.com/Muspelheim-Hosting/pterodactyl-installer/actions/workflows/shellcheck.yml/badge.svg)](https://github.com/Muspelheim-Hosting/pterodactyl-installer/actions/workflows/shellcheck.yml)
[![License: GPL v3](https://img.shields.io/github/license/Muspelheim-Hosting/pterodactyl-installer)](LICENSE)

Unofficial scripts for installing [Pyrodactyl Panel](https://github.com/pyrodactyl-oss/pyrodactyl) & [Elytra](https://github.com/pyrohost/elytra) (the daemon). Works with the latest version of Pyrodactyl!

This project is a fork of [pterodactyl-installer](https://github.com/pterodactyl-installer/pterodactyl-installer) by Vilhelm Prytz, adapted to install Pyrodactyl Panel and the Elytra daemon. It is not associated with the official Pyrodactyl or Pterodactyl projects.

## Features

- Automatic installation of the Pyrodactyl Panel (dependencies, database, cronjob, nginx, PHP 8.4, frontend build).
- Automatic installation of Elytra (Docker, systemd, optional [rustic](https://github.com/rustic-rs/rustic) backups).
- **Local / no-SSL install that works out of the box** — decline SSL and the panel is served over `http://<your-server-ip>` with no FQDN required.
- **Single-machine "both"** — when the panel and Elytra are installed together, the node and Elytra config are created automatically (no manual panel setup).
- **Separate machines** — configure Elytra against a remote panel with just a panel URL + API key (the panel installer generates one for you).
- Panel: (optional) automatic Let's Encrypt, firewall, [phpMyAdmin](https://www.phpmyadmin.net/) (port 8081), and a sample Minecraft server.
- A detailed summary at the end of the install (URL, login, database, API key, service status, next steps).
- Uninstallation support for both panel and Elytra.

## Supported installations

List of supported installation setups for panel and Elytra (installations supported by this installation script).

### Supported panel and Elytra operating systems

| Operating System | Version | Supported          | PHP Version |
| ---------------- | ------- | ------------------ | ----------- |
| Ubuntu           | 14.04   | :red_circle:       |             |
|                  | 16.04   | :red_circle: \*    |             |
|                  | 18.04   | :red_circle: \*    |             |
|                  | 20.04   | :red_circle: \*    |             |
|                  | 22.04   | :white_check_mark: | 8.4         |
|                  | 24.04   | :white_check_mark: | 8.4         |
| Debian           | 8       | :red_circle: \*    |             |
|                  | 9       | :red_circle: \*    |             |
|                  | 10      | :white_check_mark: | 8.4         |
|                  | 11      | :white_check_mark: | 8.4         |
|                  | 12      | :white_check_mark: | 8.4         |
|                  | 13      | :white_check_mark: | 8.4         |
| CentOS           | 6       | :red_circle:       |             |
|                  | 7       | :red_circle: \*    |             |
|                  | 8       | :red_circle: \*    |             |
| Rocky Linux      | 8       | :white_check_mark: | 8.4         |
|                  | 9       | :white_check_mark: | 8.4         |
| AlmaLinux        | 8       | :white_check_mark: | 8.4         |
|                  | 9       | :white_check_mark: | 8.4         |

_\* Indicates an operating system and release that previously was supported by this script._

## Using the installation scripts

To use the installation scripts, simply run this command as root. The script will ask you whether you would like to install just the panel, just Elytra or both.

```bash
bash <(curl -sSL https://raw.githubusercontent.com/Muspelheim-Hosting/pterodactyl-installer/master/install.sh)
```

_Note: On some systems, it's required to be already logged in as root before executing the one-line command (where `sudo` is in front of the command does not work)._

## Firewall setup

The installation scripts can install and configure a firewall for you. The script will ask whether you want this or not. It is highly recommended to opt-in for the automatic firewall setup.

## Development & Ops

### Testing the script locally

To test the script, we use [Vagrant](https://www.vagrantup.com). With Vagrant, you can quickly get a fresh machine up and running to test the script.

If you want to test the script on all supported installations in one go, just run the following.

```bash
vagrant up
```

If you only want to test a specific distribution, you can run the following.

```bash
vagrant up <name>
```

Replace name with one of the following (supported installations).

- `ubuntu_noble`
- `ubuntu_jammy`
- `debian_bullseye`
- `debian_buster`
- `debian_bookworm`
- `debian_trixie`
- `almalinux_8`
- `almalinux_9`
- `rockylinux_8`
- `rockylinux_9`

The project directory is mounted at `/vagrant` inside the box, so your local (un-pushed) changes are used directly. There are two ways to exercise the installer:

#### Headless install test

Runs the full install non-interactively (everything fed via env vars, no prompts):

```bash
vagrant up ubuntu_noble
vagrant provision ubuntu_noble --provision-with test-install
```

Override the target with `TEST_TARGET` (`panel` | `wings` | `both`, default `both`), e.g.:

```bash
TEST_TARGET=panel vagrant provision ubuntu_noble --provision-with test-install
```

#### Interactive test

Walks the real menu and every prompt (SSL, FQDN, phpMyAdmin, node setup) — exactly what a user sees — while still reading everything from `/vagrant`. It needs a real terminal, so SSH in and run it:

```bash
vagrant up ubuntu_noble
vagrant ssh ubuntu_noble
sudo bash /vagrant/scripts/vagrant/vagrant_test_interactive.sh
```

After install, find the VM's IP with `ip -4 addr` and open `http://<vm-ip>/` from your host to reach the panel.

### Creating a release

In `install.sh` github source and script release variables should change every release. Firstly, update the `CHANGELOG.md` so that the release date and release tag are both displayed. No changes should be made to the changelog points themselves. Secondly, update `GITHUB_SOURCE` and `SCRIPT_RELEASE` in `install.sh`. Finally, you can now push a commit with the message `Release vX.Y.Z` and create a release on GitHub.

## Credits

This project is a fork of [pterodactyl-installer](https://github.com/pterodactyl-installer/pterodactyl-installer).

Copyright (C) 2018 - 2026, Vilhelm Prytz, <vilhelm@prytznet.se>, and contributors!

- Original `pterodactyl-installer` created by [Vilhelm Prytz](https://github.com/vilhelmprytz) and maintained by [Linux123123](https://github.com/Linux123123).
