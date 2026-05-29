# -*- mode: ruby -*-
# vi: set ft=ruby :

# Which installer to run during the `test-install` provisioner.
# Override on the CLI, e.g.:
#   TEST_TARGET=both vagrant up ubuntu_noble --provision-with test-install
TEST_TARGET = ENV.fetch("TEST_TARGET", "panel")

Vagrant.configure("2") do |config|
  # "public" network so that we can access the panel interface
  config.vm.network "public_network"

  # Always (re)create the symlink to the shared lib script.
  # /tmp is wiped on reboot, and installers/*.sh source /tmp/pyrodactyl-lib.sh.
  # `run: "always"` makes this fire on every `vagrant up`, not just first boot.
  config.vm.provision "shell",
    name: "link-lib",
    run: "always",
    inline: "ln -sf /vagrant/lib/lib.sh /tmp/pyrodactyl-lib.sh"

  # Opt-in provisioner that drives a full, non-interactive install.
  # Usage:
  #   vagrant up <name>                                  # just brings the box up
  #   vagrant up <name> --provision-with test-install    # brings it up AND installs
  #   vagrant provision <name> --provision-with test-install  # re-run on existing box
  config.vm.provision "test-install",
    type: "shell",
    run: "never",
    privileged: true,
    env: { "TEST_TARGET" => TEST_TARGET },
    inline: <<~SHELL
      set -e
      ln -sf /vagrant/lib/lib.sh /tmp/pyrodactyl-lib.sh
      bash /vagrant/scripts/vagrant/vagrant_test_installer.sh "$TEST_TARGET"
    SHELL

  # Opt-in interactive test: boots the SAME menu as install.sh (defined once in
  # lib/lib.sh as `main_menu`) and walks every prompt, then installs. It needs a
  # real TTY, so the reliable way is to SSH in and run it by hand:
  #   vagrant up <name>
  #   vagrant ssh <name>
  #   sudo /vagrant/scripts/vagrant/vagrant_test_interactive.sh
  # The provisioner below is a convenience for providers that forward stdin:
  #   vagrant provision <name> --provision-with test-interactive
  config.vm.provision "test-interactive",
    type: "shell",
    run: "never",
    privileged: true,
    inline: <<~SHELL
      set -e
      ln -sf /vagrant/lib/lib.sh /tmp/pyrodactyl-lib.sh
      bash /vagrant/scripts/vagrant/vagrant_test_interactive.sh
    SHELL

  # Define Ubuntu VMs
  config.vm.define "ubuntu_noble" do |ubuntu_noble|
    ubuntu_noble.vm.box = "alvistack/ubuntu-24.04"
    ubuntu_noble.vm.provider "virtualbox" do |vb|
      vb.memory = "4096"
    end
  end

  config.vm.define "ubuntu_jammy" do |ubuntu_jammy|
    ubuntu_jammy.vm.box = "ubuntu/jammy64"
    ubuntu_jammy.vm.provider "virtualbox" do |vb|
      vb.memory = "4096"
    end
  end

  # Define Debian VMs
  config.vm.define "debian_bullseye" do |debian_bullseye|
    debian_bullseye.vm.box = "debian/bullseye64"
    debian_bullseye.vm.provider "virtualbox" do |vb|
      vb.memory = "4096"
    end
  end

  config.vm.define "debian_buster" do |debian_buster|
    debian_buster.vm.box = "debian/buster64"
    debian_buster.vm.provider "virtualbox" do |vb|
      vb.memory = "4096"
    end
  end

  config.vm.define "debian_bookworm" do |debian_bookworm|
    debian_bookworm.vm.box = "debian/bookworm64"
    debian_bookworm.vm.provider "virtualbox" do |vb|
      vb.memory = "4096"
    end
  end

  config.vm.define "debian_trixie" do |debian_trixie|
    debian_trixie.vm.box = "debian/trixie64"
    debian_trixie.vm.provider "virtualbox" do |vb|
      vb.memory = "4096"
    end
  end

  # Define AlmaLinux VMs
  config.vm.define "almalinux_8" do |almalinux_8|
    almalinux_8.vm.box = "almalinux/8"
    almalinux_8.vm.provider "virtualbox" do |vb|
      vb.memory = "4096"
    end
  end

  config.vm.define "almalinux_9" do |almalinux_9|
    almalinux_9.vm.box = "almalinux/9"
    almalinux_9.vm.provider "virtualbox" do |vb|
      vb.memory = "4096"
    end
  end

  # Define Rocky Linux VMs
  config.vm.define "rockylinux_8" do |rockylinux_8|
    rockylinux_8.vm.box = "bento/rockylinux-8"
    rockylinux_8.vm.provider "virtualbox" do |vb|
      vb.memory = "4096"
    end
  end

  config.vm.define "rockylinux_9" do |rockylinux_9|
    rockylinux_9.vm.box = "bento/rockylinux-9"
    rockylinux_9.vm.provider "virtualbox" do |vb|
      vb.memory = "4096"
    end
  end
end
