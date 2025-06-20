#!/usr/bin/env bash
# Arch + Hyprland quick‑setup (systemd‑boot only)
# ---------------------------------------------
# Adds: mirror ranking, btrfs snapshot, unified logging, coloured ERR trap,
#        auto‑detect kernel headers.

set -euo pipefail

# ------------- GLOBAL GUARDS & LOGGING -------------
exec > >(tee -i /var/log/hypr-setup.log) 2>&1
trap 'echo -e "\e[1;31m‼  Error on line $LINENO – exiting.\e[0m"' ERR

# ------------- DETECT USER -------------------------
USER_NAME="${SUDO_USER:?Run with sudo (e.g. sudo ./hypr-setup.sh)}"
USER_HOME=$(getent passwd "$USER_NAME" | cut -d: -f6)
DOTFILES_REPO="${DOTFILES_REPO:-https://github.com/sb74/dotfiles.git}"

# ------------- PACKAGE LISTS -----------------------
PACMAN_ESSENTIALS=(
  git base-devel rsync fish starship wget unzip jq fzf eza htop btop neovim xclip tldr
  firefox ripgrep fd lazygit nodejs npm rust cargo python python-pip file tree zip p7zip
  man-db man-pages lsof reflector
)

PACMAN_GUI_STACK=(
  hyprland hyprpaper hyprlock hypridle hyprpicker waybar rofi-wayland mako wlogout ghostty
  pipewire wireplumber pavucontrol pamixer networkmanager network-manager-applet
  xdg-desktop-portal-hyprland xdg-desktop-portal-gtk greetd tuigreet polkit-gnome grim
  slurp cliphist nwg-look noto-fonts noto-fonts-emoji ttf-fira-code ttf-firacode-nerd
  otf-font-awesome papirus-icon-theme gammastep thunar libnotify wl-clipboard nvidia
  nvidia-utils nvidia-settings # kernel headers added dynamically
)

AUR_TOOLS=(
  wl-gammarelay-rs pyprland wallust waypaper protonup-qt warp-terminal obsidian windsurf-bin
)

# ------------- PROGRESS BAR ------------------------
TOTAL_STEPS=15
CURRENT_STEP=0
progress() {
  ((CURRENT_STEP++))
  echo -e "\n\033[1;34m[$CURRENT_STEP/$TOTAL_STEPS] $1\033[0m"
}

confirm() {
  read -rp "${1:-Continue?} [y/N]: " r
  [[ $r =~ ^[Yy]$ ]]
}
run_as_user() { sudo -u "$USER_NAME" "$@"; }

# ------------- TASKS -------------------------------
check_root() {
  progress "🔑 Checking root privileges"
  [[ $EUID -eq 0 ]] || {
    echo "Run with sudo"
    exit 1
  }
}

create_snapshot() {
  progress "📸 Btrfs snapshot (pre‑install)"
  if mount | grep -q " on / .*btrfs"; then
    SNAP_DIR="/.snapshots/pre-hypr-$(date +%Y%m%d-%H%M%S)"
    btrfs subvolume snapshot / "$SNAP_DIR"
    echo "Snapshot created at $SNAP_DIR"
  else
    echo "Root is not btrfs – skipping snapshot."
  fi
}

rank_mirrors() {
  progress "🌐 Ranking fastest mirrors"
  pacman -Sy --noconfirm reflector
  reflector --country $(curl -s https://ipapi.co/country/ 2>/dev/null || echo "US,GB") \
    --latest 20 --sort rate --save /etc/pacman.d/mirrorlist
}

update_system() {
  progress "📦 pacman -Syu"
  pacman -Syu --noconfirm
}
install_essentials() {
  progress "🔧 Essentials"
  pacman -S --needed --noconfirm "${PACMAN_ESSENTIALS[@]}"
}
set_fish_shell() {
  progress "🐟 Set fish default"
  cur_shell=$(getent passwd "$USER_NAME" | cut -d: -f7)
  [[ $cur_shell == /usr/bin/fish ]] || chsh -s /usr/bin/fish "$USER_NAME"
}
install_yay() {
  progress "📦 yay (AUR helper)"
  command -v yay >/dev/null && {
    echo "yay exists"
    return
  }
  pacman -S --needed --noconfirm git base-devel
  tmp=$(mktemp -d)
  git clone https://aur.archlinux.org/yay.git "$tmp"
  chown -R "$USER_NAME":"$USER_NAME" "$tmp"
  pushd "$tmp" >/dev/null
  run_as_user makepkg -si --noconfirm
  popd >/dev/null
  rm -rf "$tmp"
}
install_kernel_headers() {
  progress "📚 Kernel headers"
  case $(uname -r) in
  *lts*) pkg=linux-lts-headers ;;
  *zen*) pkg=linux-zen-headers ;;
  *) pkg=linux-headers ;;
  esac
  pacman -S --needed --noconfirm "$pkg"
}
install_gui_stack() {
  progress "💡 GUI stack"
  pacman -S --needed --noconfirm "${PACMAN_GUI_STACK[@]}"
}
setup_nvidia_wayland() {
  progress "🎮 NVIDIA (systemd‑boot)"
  grep -q nvidia_drm /etc/mkinitcpio.conf || {
    sed -i 's/MODULES=(/MODULES=(nvidia nvidia_modeset nvidia_uvm nvidia_drm /' /etc/mkinitcpio.conf
    mkinitcpio -P
  }
  for entry in /boot/loader/entries/*.conf; do
    grep -q "nvidia-drm.modeset=1" "$entry" && continue
    sed -i 's/^options /options nvidia-drm.modeset=1 /' "$entry"
  done
  echo "⚠️  Reboot required for NVIDIA changes."
}
install_gaming_tools() {
  progress "🎮 Steam"
  pacman -S --needed --noconfirm steam
}
install_aur_tools() {
  progress "🎨 AUR tools"
  run_as_user yay -S --needed --noconfirm "${AUR_TOOLS[@]}"
}
enable_services() {
  progress "🧩 Enabling services"
  systemctl enable greetd NetworkManager
  loginctl enable-linger "$USER_NAME"
}
setup_dotfiles_chezmoi() {
  progress "🛠️  Chezmoi dotfiles"
  run_as_user yay -S --needed --noconfirm chezmoi
  if [[ ! -d "$USER_HOME/.local/share/chezmoi" ]]; then
    run_as_user chezmoi init "$DOTFILES_REPO" || run_as_user chezmoi init
  fi
  run_as_user chezmoi apply
}
setup_neovim() {
  progress "📝 LazyVim"
  run_as_user fish -c 'set -Ux EDITOR nvim'
  cfg="$USER_HOME/.config/nvim"
  if [[ ! -d $cfg ]]; then
    run_as_user git clone https://github.com/LazyVim/starter "$cfg"
    run_as_user rm -rf "$cfg/.git"
  fi
}

# ------------- MAIN FLOW ---------------------------
run_all() {
  check_root
  create_snapshot
  rank_mirrors
  update_system
  install_essentials
  set_fish_shell
  install_yay
  install_kernel_headers
  install_gui_stack
  setup_nvidia_wayland
  install_gaming_tools
  install_aur_tools
  enable_services
  setup_dotfiles_chezmoi
  setup_neovim
  echo -e "\n\033[1;32m✅ Done — reboot and enjoy Hyprland!\033[0m"
}

clear
echo "Arch Hyprland quick‑setup for $USER_NAME"
echo "========================================"

sudo -v
while true; do
  sudo -n true
  sleep 60
  kill -0 "$${BASHPID:-$$}" || exit
done &
keep=$!
trap 'kill $keep 2>/dev/null' EXIT

if confirm "Run full automated setup?"; then
  run_all
else
  echo "Interactive mode not supported in this script."
fi
