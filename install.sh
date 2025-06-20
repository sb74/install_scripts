#!/usr/bin/env bash
# Fail on error, unset variable, or pipe failure
set -euo pipefail

# --- CONFIGURATION ---
# Improved User Detection: Automatically detect the user who ran sudo.
# Fallback to 'sb74' if detection fails.
USER_NAME="${SUDO_USER:-sb74}"
USER_HOME=$(getent passwd "$USER_NAME" | cut -d: -f6)

# Optional dotfiles repo override for flexibility
DOTFILES_REPO="${DOTFILES_REPO:-https://github.com/sb74/dotfiles.git}"

# Package Lists as Arrays: Easier to manage and read.
PACMAN_ESSENTIALS=(
  git base-devel rsync fish starship wget unzip jq fzf eza htop btop neovim xclip tldr
  firefox ripgrep fd lazygit nodejs npm rust cargo
  python python-pip file tree zip p7zip man-db man-pages lsof
)
PACMAN_GUI_STACK=(
  hyprland hyprpaper hyprlock hypridle hyprpicker
  waybar rofi-wayland mako wlogout ghostty
  pipewire wireplumber pavucontrol pamixer
  networkmanager network-manager-applet
  xdg-desktop-portal-hyprland xdg-desktop-portal-gtk
  greetd tuigreet polkit-gnome grim slurp cliphist
  nwg-look
  noto-fonts noto-fonts-emoji ttf-fira-code ttf-firacode-nerd otf-font-awesome papirus-icon-theme
  gammastep thunar libnotify wl-clipboard
  nvidia nvidia-utils nvidia-settings linux-headers
)
AUR_TOOLS=(
  wl-gammarelay-rs
  pyprland
  wallust
  waypaper
  protonup-qt
  warp-terminal
  obsidian
  windsurf-bin
)
# --- END CONFIGURATION ---

TOTAL_STEPS=11
CURRENT_STEP=0
# Auto-enable DRY_RUN in CI environments
[[ "${CI:-}" == "true" ]] && DRY_RUN=true
DRY_RUN="${DRY_RUN:-false}"

# --- HELPER FUNCTIONS ---
function progress() {
  CURRENT_STEP=$((CURRENT_STEP + 1))
  # Use bold blue for better visibility
  echo -e "\n\033[1;34m[$CURRENT_STEP/$TOTAL_STEPS] $1\033[0m"
}

function confirm() {
  # Added a default prompt if one isn't provided
  read -rp "${1:-Are you sure?} [y/N]: " response
  [[ "$response" =~ ^[Yy]$ ]]
}

function run_cmd() {
  if [[ "$DRY_RUN" == "true" ]]; then
    echo "[DRY RUN] $*"
  else
    "$@"
  fi
}

# Helper to run commands as the regular user
function run_as_user() {
  if [[ "$DRY_RUN" == "true" ]]; then
    echo "[DRY RUN] sudo -u $USER_NAME $*"
  else
    sudo -u "$USER_NAME" "$@"
  fi
}

# --- SETUP FUNCTIONS ---
function check_root() {
  progress "🔑 Checking for root privileges..."
  if [[ "$EUID" -ne 0 ]]; then
    echo "❌ This script must be run with sudo: sudo ./setup.sh"
    exit 1
  fi
  echo "Root privileges confirmed. User: $USER_NAME ($USER_HOME)"
}

function update_system() {
  progress "📦 Updating base system..."
  run_cmd pacman -Syu --noconfirm
}

function install_essentials() {
  progress "🔧 Installing essential tools..."
  run_cmd pacman -S --needed --noconfirm "${PACMAN_ESSENTIALS[@]}"
}

function set_fish_shell() {
  progress "🐟 Setting default shell to fish..."
  # Idempotency: Only change the shell if it's not already fish
  local current_shell
  current_shell=$(getent passwd "$USER_NAME" | cut -d: -f7)
  if [[ "$current_shell" != "/usr/bin/fish" ]]; then
    run_cmd chsh -s /usr/bin/fish "$USER_NAME"
    echo "Default shell for user '$USER_NAME' set to fish (root shell unchanged)."
  else
    echo "Default shell is already fish."
  fi
}

function install_yay() {
  progress "📦 Bootstrapping yay (AUR helper)..."
  if command -v yay >/dev/null 2>&1; then
    echo "yay is already installed."
    return
  fi

  # Prerequisite Check: Ensure git and base-devel are installed first
  echo "Checking for git and base-devel..."
  run_cmd pacman -S --needed --noconfirm git base-devel

  local yay_dir="/tmp/yay"
  # 🔥 Clean up temp dir if script exits unexpectedly
  trap 'rm -rf "$yay_dir"' EXIT

  echo "Cloning yay repository to $yay_dir..."
  run_cmd git clone https://aur.archlinux.org/yay.git "$yay_dir"
  # Set correct ownership for the user to build the package
  run_cmd chown -R "$USER_NAME:$USER_NAME" "$yay_dir"

  pushd "$yay_dir" || exit 1
  run_as_user makepkg -si --noconfirm
  popd || exit 1
  # Manual cleanup (trap will also handle this)
  run_cmd rm -rf "$yay_dir"
}

function install_gui_stack() {
  progress "💡 Installing GUI/Wayland stack (greetd version)..."
  run_cmd pacman -S --needed --noconfirm "${PACMAN_GUI_STACK[@]}"
}

function setup_nvidia_wayland() {
  progress "🎮 Configuring NVIDIA for Wayland..."

  # Add NVIDIA modules to mkinitcpio
  if ! grep -q "nvidia" /etc/mkinitcpio.conf; then
    echo "Adding NVIDIA modules to mkinitcpio..."
    run_cmd sed -i 's/MODULES=(/MODULES=(nvidia nvidia_modeset nvidia_uvm nvidia_drm /' /etc/mkinitcpio.conf
    run_cmd mkinitcpio -P
  else
    echo "NVIDIA modules already in mkinitcpio.conf"
  fi

  # Enable DRM kernel mode setting
  if ! grep -q "nvidia-drm.modeset=1" /etc/default/grub; then
    echo "Enabling NVIDIA DRM kernel mode setting..."
    run_cmd sed -i 's/GRUB_CMDLINE_LINUX_DEFAULT="/&nvidia-drm.modeset=1 /' /etc/default/grub
    run_cmd grub-mkconfig -o /boot/grub/grub.cfg
  else
    echo "NVIDIA DRM modeset already enabled"
  fi

  echo "⚠️ REBOOT REQUIRED for NVIDIA changes to take effect!"
}

function install_gaming_tools() {
  progress "🎮 Installing Steam and gaming tools..."
  run_cmd pacman -S --needed --noconfirm steam
}

function install_aur_tools() {
  progress "🎨 Installing AUR/optional tools..."
  # Prerequisite: Ensure yay is installed
  if ! command -v yay >/dev/null 2>&1; then
    echo "⚠️ yay not found. Skipping AUR packages. Please install yay first."
    return
  fi
  run_as_user yay -S --needed --noconfirm "${AUR_TOOLS[@]}"
}

function enable_services() {
  progress "🧩 Enabling system services..."
  run_cmd systemctl enable greetd
  run_cmd systemctl enable NetworkManager

  # Enable linger to allow user services (like PipeWire) to run even when the user is not logged in.
  run_cmd loginctl enable-linger "$USER_NAME"

  # Note: PipeWire user services often auto-start via socket activation
  echo "ℹ️ PipeWire will auto-start via socket activation or from dotfiles."
  echo "💡 If needed manually: systemctl --user enable pipewire wireplumber"
}

function setup_dotfiles_chezmoi() {
  progress "🛠️ Setting up dotfiles with chezmoi..."

  # Always install chezmoi first
  echo "Installing chezmoi..."
  run_as_user yay -S --needed --noconfirm chezmoi

  # Idempotency: Only init chezmoi if it hasn't been initialized yet
  local chezmoi_dir="$USER_HOME/.local/share/chezmoi"
  if [[ ! -d "$chezmoi_dir" ]]; then
    echo "Initializing chezmoi with dotfiles repo: $DOTFILES_REPO"

    # Try to initialize with your repo (might fail if private/no SSH keys)
    if run_as_user chezmoi init "$DOTFILES_REPO"; then
      echo "✅ Successfully initialized chezmoi with remote repo."
      if run_as_user chezmoi apply; then
        echo "✅ Dotfiles applied successfully."
      else
        echo "⚠️ Failed to apply dotfiles. You can run 'chezmoi apply' manually later."
      fi
    else
      echo "⚠️ Failed to initialize with remote repo (might be private or need SSH keys)."
      echo "📝 Initializing empty chezmoi repo instead..."
      run_as_user chezmoi init
      echo "💡 You can later run: chezmoi init $DOTFILES_REPO"
    fi
  else
    echo "chezmoi appears to be already initialized."
    echo "Running 'chezmoi apply' to sync any changes..."
    if run_as_user chezmoi apply; then
      echo "✅ Dotfiles synced successfully."
    else
      echo "⚠️ Failed to apply dotfiles. Check 'chezmoi status' for issues."
    fi
  fi

  echo "🪪 greetd config will use system default unless overridden by your dotfiles."
}

function setup_neovim() {
  progress "📝 Setting up Neovim with LazyVim..."
  # Set default editor
  run_as_user fish -c 'set -Ux EDITOR nvim'

  local nvim_config_dir="$USER_HOME/.config/nvim"

  # Idempotency: Only install if the config directory doesn't exist
  if [[ -d "$nvim_config_dir" ]]; then
    echo "Neovim config at $nvim_config_dir already exists. Skipping LazyVim installation."
    return
  fi

  echo "Cloning LazyVim starter..."
  run_as_user git clone https://github.com/LazyVim/starter "$nvim_config_dir"
  run_as_user rm -rf "$nvim_config_dir/.git"
  echo "LazyVim installed."
}

# --- SCRIPT EXECUTION ---
function run_all() {
  check_root
  update_system
  install_essentials
  set_fish_shell
  install_yay
  install_gui_stack
  setup_nvidia_wayland
  install_gaming_tools
  install_aur_tools
  enable_services
  setup_dotfiles_chezmoi
  setup_neovim
  echo -e "\n\033[1;32m✅ Full setup complete! Reboot and enjoy your greetd + Hyprland system.\033[0m"
}

# --- Main Logic ---
clear
echo "========================================"
echo "  Arch Hyprland Setup Script  "
echo "  User: $USER_NAME ($USER_HOME)"
echo "========================================"

# Keep sudo session alive
# This will prompt for the password once at the start
# and then silently refresh the timestamp in the background.
echo "Requesting sudo access for the script..."
sudo -v
while true; do
  sudo -n true
  sleep 60
  kill -0 "$$" || exit
done 2>/dev/null &

if confirm "🚀 Run full automated setup?"; then
  run_all
else
  echo "Entering interactive mode..."
  check_root
  confirm "📦 Update system?" && update_system
  confirm "🔧 Install essentials?" && install_essentials
  confirm "🐟 Set fish shell?" && set_fish_shell
  confirm "📦 Install yay?" && install_yay
  confirm "💡 Install GUI stack?" && install_gui_stack
  confirm "🎮 Setup NVIDIA?" && setup_nvidia_wayland
  confirm "🎮 Install gaming tools?" && install_gaming_tools
  confirm "🎨 Install AUR tools?" && install_aur_tools
  confirm "🧩 Enable services?" && enable_services
  confirm "🛠️ Setup dotfiles with chezmoi?" && setup_dotfiles_chezmoi
  confirm "📝 Setup Neovim?" && setup_neovim
  echo -e "\n\033[1;33m⚙️ Partial install complete. Reboot when ready.\033[0m"
fi
