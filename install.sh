#!/usr/bin/env bash
set -euo pipefail

USER_NAME="sb74"
TOTAL_STEPS=9
CURRENT_STEP=0

function progress() {
  CURRENT_STEP=$((CURRENT_STEP + 1))
  echo -e "\n[$CURRENT_STEP/$TOTAL_STEPS] $1"
}

function confirm() {
  read -rp "$1 [y/N]: " response
  [[ "$response" =~ ^[Yy]$ ]]
}

function update_system() {
  progress "📦 Updating base system..."
  sudo pacman -Syu --noconfirm
}

function install_essentials() {
  progress "🔧 Installing essential tools..."
  sudo pacman -S --needed --noconfirm \
    git base-devel rsync fish starship wget unzip jq fzf eza htop btop neovim xclip tldr \
    firefox ripgrep fd lazygit nodejs npm rust cargo \
    python python-pip file tree zip p7zip man-db man-pages lsof
}

function set_fish_shell() {
  progress "🐟 Setting default shell to fish..."
  sudo chsh -s /usr/bin/fish "$USER_NAME"
}

function install_yay() {
  progress "📦 Bootstrapping yay (AUR helper)..."
  if ! command -v yay >/dev/null 2>&1; then
    git clone https://aur.archlinux.org/yay.git /tmp/yay
    pushd /tmp/yay
    makepkg -si --noconfirm
    popd
  else
    echo "yay already installed."
  fi
}

function install_gui_stack() {
  progress "💡 Installing GUI/Wayland stack (greetd version)..."
  sudo pacman -S --needed --noconfirm \
    hyprland hyprpaper hyprlock hypridle hyprpicker \
    waybar rofi-wayland mako wlogout ghostty \
    pipewire wireplumber pavucontrol pamixer \
    networkmanager network-manager-applet \
    xdg-desktop-portal-hyprland xdg-desktop-portal-gtk \
    greetd tuigreet polkit-gnome grim slurp cliphist \
    nwg-look \
    noto-fonts noto-fonts-emoji ttf-fira-code ttf-firacode-nerd otf-font-awesome papirus-icon-theme \
    gammastep thunar libnotify wl-clipboard
}

function install_gaming_tools() {
  progress "🎮 Installing Steam and gaming tools..."
  sudo pacman -S --needed --noconfirm steam
}

function install_aur_tools() {
  progress "🎨 Installing AUR/optional tools..."
  yay -S --needed --noconfirm \
    wl-gammarelay-rs \
    pyprland \
    wallust \
    waypaper \
    protonup-qt \
    warp-terminal `# Testing alongside ghostty` \
    obsidian \
    windsurf-bin
}

function enable_services() {
  progress "🧩 Enabling system services..."
  sudo systemctl enable greetd
  sudo systemctl enable NetworkManager
  loginctl enable-linger "$USER_NAME"

  # Enable pipewire user services
  sudo -u "$USER_NAME" systemctl --user enable pipewire
  sudo -u "$USER_NAME" systemctl --user enable wireplumber
}

function install_dotfiles_chezmoi() {
  progress "🛠️ Installing chezmoi and setting up dotfiles..."
  yay -S --needed --noconfirm chezmoi
  sudo -u "$USER_NAME" chezmoi init

  CONFIG_FILES=(
    hypr/hyprland.conf
    waybar/config
    waybar/style.css
    rofi/config.rasi
    mako/config
    ghostty/config
    fish/config.fish
    thunar/uca.xml
  )

  for file in "${CONFIG_FILES[@]}"; do
    path="/home/$USER_NAME/.config/$file"
    if [[ -f "$path" ]]; then
      sudo -u "$USER_NAME" chezmoi add "$path"
    fi
  done

  echo "🪪 greetd config will use system default unless overridden manually."
}

function set_default_editor() {
  progress "📝 Setting up Neovim with LazyVim..."
  sudo -u "$USER_NAME" fish -c 'set -Ux EDITOR nvim'

  # Install LazyVim
  sudo -u "$USER_NAME" git clone https://github.com/LazyVim/starter "/home/$USER_NAME/.config/nvim"
  sudo -u "$USER_NAME" rm -rf "/home/$USER_NAME/.config/nvim/.git"
  sudo -u "$USER_NAME" chezmoi add "/home/$USER_NAME/.config/nvim"
}

function run_all() {
  update_system
  install_essentials
  set_fish_shell
  install_yay
  install_gui_stack
  install_gaming_tools
  install_aur_tools
  enable_services
  install_dotfiles_chezmoi
  set_default_editor
  echo -e "\n✅ Install complete! Reboot and enjoy your greetd + Hyprland system."
}

# === INTERACTIVE MODE ===
echo "==== Arch Setup Script for $USER_NAME ===="
echo "=========================================="

if confirm "Run full setup?"; then
  run_all
else
  confirm "Update system?" && update_system
  confirm "Install essentials?" && install_essentials
  confirm "Set fish shell?" && set_fish_shell
  confirm "Install yay?" && install_yay
  confirm "Install GUI stack?" && install_gui_stack
  confirm "Install gaming tools?" && install_gaming_tools
  confirm "Install AUR tools?" && install_aur_tools
  confirm "Enable services?" && enable_services
  confirm "Install chezmoi and dotfiles?" && install_dotfiles_chezmoi
  confirm "Set Neovim as default editor?" && set_default_editor
  echo -e "\n⚙️ Partial install complete. Reboot when ready."
fi
