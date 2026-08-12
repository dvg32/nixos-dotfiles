#!/usr/bin/env bash
set -euo pipefail

if [[ $EUID -ne 0 ]]; then
  echo "Error: This script must be run as root." >&2
  exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Prompt for user parameters
read -rp "Enter target disk for GRUB (default: /dev/sda): " GRUB_DEVICE
GRUB_DEVICE="${GRUB_DEVICE:-/dev/sda}"

read -rp "Enter primary username: " USERNAME
if [[ -z "$USERNAME" ]]; then
  echo "Error: Username cannot be empty." >&2
  exit 1
fi

TARGET_HOME="/mnt/home/$USERNAME"
TARGET_NIX_DIR="/mnt/etc/nixos"

echo "[1/6] Creating directory structures..."
mkdir -p "$TARGET_NIX_DIR"
mkdir -p "$TARGET_HOME/Walls" "$TARGET_HOME/.config"

echo "[2/6] Generating $TARGET_NIX_DIR/configuration.nix..."
cat <<EOF > "$TARGET_NIX_DIR/configuration.nix"
{ config, lib, pkgs, ... }:

let
  commonVimConfig = ''
    syntax on
    set number
    set relativenumber
    set tabstop=2
    set shiftwidth=2
    set softtabstop=2
    set expandtab
  '';
in
{
  imports =
    [ # Include the results of the hardware scan.
      ./hardware-configuration.nix
    ];

  boot.loader.grub.enable = true;
  boot.loader.grub.device = "${GRUB_DEVICE}";
  boot.loader.systemd-boot.enable = false;

  virtualisation.virtualbox.guest.enable = true;

  networking.hostName = "nixos-vbox";
  networking.networkmanager.enable = true;

  time.timeZone = "Asia/Makassar";

  services.xserver = {
    enable = true;
    windowManager.qtile.enable = true;
  };

  services.picom = {
    enable = true;
    backend = "xrender";
    fade = true;
  };

  users.users.${USERNAME} = {
    isNormalUser = true;
    extraGroups = [ "wheel" ];
    packages = with pkgs; [
      tree
    ];
  };

  programs.firefox.enable = true;

  programs.neovim = {
    enable = true;
    defaultEditor = true;
    configure = {
      customRC = commonVimConfig;
    };
  };

  environment.systemPackages = with pkgs; [
    (vim-full.customize {
      name = "vim";
      vimrcConfig.customRC = commonVimConfig;
    })
    wget
    git
    alacritty
    btop
    gedit
    kdePackages.audiotube
    gst_all_1.gstreamer
    gst_all_1.gst-plugins-base
    gst_all_1.gst-plugins-good
    gst_all_1.gst-plugins-bad
    gst_all_1.gst-plugins-ugly
    gst_all_1.gst-libav
    xwallpaper
    pcmanfm
    rofi
    gh
    pfetch
    kdePackages.gwenview
  ];

  fonts.packages = with pkgs; [
    jetbrains-mono
  ];

  services.openssh = {
    enable = true;
    settings = {
      PermitRootLogin = "prohibit-password";
      PasswordAuthentication = true;
    };
    openFirewall = true;
  };

  system.stateVersion = "26.05";
}
EOF

echo "[3/6] Generating hardware-configuration.nix..."
nixos-generate-config --root /mnt

echo "[4/6] Staging dotfiles and wallpapers..."
nix-shell -p wget --run "wget https://gruvbox-wallpapers.pages.dev/wallpapers/anime/tanjiro-kamado-gruv.jpg -P $TARGET_HOME/Walls"

for config_dir in alacritty qtile; do
  if [[ -d "$SCRIPT_DIR/$config_dir" ]]; then
    cp -r "$SCRIPT_DIR/$config_dir" "$TARGET_HOME/.config/"
    echo " -> Copied $config_dir to $TARGET_HOME/.config/"
  else
    echo " -> Warning: $SCRIPT_DIR/$config_dir not found. Skipping." >&2
  fi
done

# Fix file permissions for user UID/GID 1000
chown -R 1000:1000 "$TARGET_HOME"

echo "[5/6] Validating Nix configuration syntax..."
NIXOS_CONFIG="$TARGET_NIX_DIR/configuration.nix" nix-instantiate --parse "$TARGET_NIX_DIR/configuration.nix" > /dev/null
echo " -> Configuration syntax valid."

echo "[6/6] Installation execution."
read -rp "Continue to nixos-install? (y/N): " CONFIRM
if [[ "$CONFIRM" =~ ^[Yy]$ ]]; then
  nixos-install
  echo "Setting password for user '$USERNAME'..."
  nixos-enter --root /mnt -c "passwd $USERNAME"
  echo "Installation complete. You may now reboot."
else
  echo "Setup finished without running nixos-install. Files are staged at /mnt."
fi
