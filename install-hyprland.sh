#!/bin/bash

#############################################
# Hyprland Automated Install Script
# For Arch Linux (fresh minimal install)
# Based on typecraft's Hyprland tutorial series
#############################################

set -e  # Exit on error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
DOTFILES_REPO="https://github.com/maxhu08/dotfiles"
WALLPAPERS_REPO="https://github.com/maxhu08/wallpapers"
REBOS_CONFIG_REPO="https://github.com/maxhu08/rebos-config-arch"

# Function to print colored output
print_status() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

# Check if running as root
check_root() {
    if [[ $EUID -eq 0 ]]; then
        print_error "This script should not be run as root!"
        print_status "Please run as a normal user with sudo privileges."
        exit 1
    fi
}

# Update system
update_system() {
    print_status "Updating system packages..."
    sudo pacman -Syu --noconfirm
    print_success "System updated!"
}

# Install yay AUR helper
install_yay() {
    if ! command -v yay &> /dev/null; then
        print_status "Installing yay AUR helper..."
        sudo pacman -S --needed --noconfirm git base-devel
        git clone https://aur.archlinux.org/yay.git /tmp/yay
        cd /tmp/yay
        makepkg -si --noconfirm
        cd -
        rm -rf /tmp/yay
        print_success "yay installed!"
    else
        print_status "yay is already installed"
    fi
}

# Install essential packages
install_essential_packages() {
    print_status "Installing essential packages..."
    
    # Core packages
    local packages=(
        # Terminal and shell
        kitty
        zsh
        starship
        
        # Window manager and compositor
        hyprland
        xdg-desktop-portal-hyprland
        
        # Hypr ecosystem tools
        hyprpaper
        hypridle
        hyprlock
        hyprshot
        
        # Application launcher and bar
        wofi
        waybar
        
        # Notifications
        swaync
        libnotify
        
        # File management
        nautilus
        thunar
        
        # System utilities
        brightnessctl
        pamixer
        playerctl
        grim
        slurp
        wl-clipboard
        cliphist
        
        # Fonts
        ttf-font-awesome
        ttf-cascadia-code-nerd
        noto-fonts
        noto-fonts-emoji
        
        # Development tools
        git
        stow
        neovim
        
        # Network and bluetooth
        networkmanager
        network-manager-applet
        bluez
        bluez-utils
        blueman
        
        # Audio
        pipewire
        pipewire-pulse
        pipewire-alsa
        pipewire-jack
        wireplumber
        
        # Theme tools
        nwg-look
        qt5ct
        qt6ct
        kvantum
        
        # Other utilities
        polkit-gnome
        xdg-utils
        xdg-user-dirs
        gtk3
        gtk4
    )
    
    print_status "Installing packages with pacman..."
    sudo pacman -S --needed --noconfirm "${packages[@]}"
    
    print_success "Essential packages installed!"
}

# Install AUR packages
install_aur_packages() {
    print_status "Installing AUR packages..."
    
    local aur_packages=(
        # Themes
        catppuccin-gtk-theme-mocha
        catppuccin-cursors-mocha
        
        # Additional fonts
        ttf-meslo-nerd-font-powerlevel10k
        
        # Additional tools
        hyprpicker
    )
    
    for package in "${aur_packages[@]}"; do
        print_status "Installing $package from AUR..."
        yay -S --noconfirm "$package" || print_warning "Failed to install $package, continuing..."
    done
    
    print_success "AUR packages installed!"
}

# Create necessary directories
create_directories() {
    print_status "Creating necessary directories..."
    
    mkdir -p ~/.config
    mkdir -p ~/.local/share/applications
    mkdir -p ~/.local/share/fonts
    mkdir -p ~/Pictures/Screenshots
    mkdir -p ~/Pictures/Wallpapers
    mkdir -p ~/Documents
    mkdir -p ~/Downloads
    
    # Create XDG user directories
    xdg-user-dirs-update
    
    print_success "Directories created!"
}

# Clone and setup dotfiles
setup_dotfiles() {
    print_status "Setting up dotfiles..."
    
    # Backup existing configs
    if [ -d ~/.config ]; then
        print_status "Backing up existing configs..."
        cp -r ~/.config ~/.config.backup.$(date +%Y%m%d_%H%M%S)
    fi
    
    # Clone dotfiles repository
    if [ ! -d ~/dotfiles ]; then
        print_status "Cloning dotfiles repository..."
        git clone "$DOTFILES_REPO" ~/dotfiles
    else
        print_status "Dotfiles repository already exists, pulling latest changes..."
        cd ~/dotfiles && git pull && cd -
    fi
    
    # Clone wallpapers repository
    if [ ! -d ~/Pictures/Wallpapers/maxhu08 ]; then
        print_status "Cloning wallpapers repository..."
        git clone "$WALLPAPERS_REPO" ~/Pictures/Wallpapers/maxhu08
    else
        print_status "Wallpapers repository already exists, pulling latest changes..."
        cd ~/Pictures/Wallpapers/maxhu08 && git pull && cd -
    fi
    
    # Use stow to create symlinks for configurations
    cd ~/dotfiles
    
    # Remove any existing configs that might conflict
    local configs=(
        hyprland
        hyprpaper
        hypridle
        hyprlock
        waybar
        wofi
        kitty
        starship
        swaync
        gtk-3.0
        gtk-4.0
    )
    
    for config in "${configs[@]}"; do
        if [ -d ~/.config/"$config" ] && [ ! -L ~/.config/"$config" ]; then
            print_warning "Removing existing $config config..."
            rm -rf ~/.config/"$config"
        fi
    done
    
    # Stow configurations
    print_status "Creating configuration symlinks..."
    for config in "${configs[@]}"; do
        if [ -d "$config" ]; then
            print_status "Stowing $config..."
            stow -v "$config" || print_warning "Failed to stow $config, continuing..."
        fi
    done
    
    cd -
    print_success "Dotfiles setup complete!"
}

# Configure shell
configure_shell() {
    print_status "Configuring shell..."
    
    # Install oh-my-zsh if not already installed
    if [ ! -d "$HOME/.oh-my-zsh" ]; then
        print_status "Installing Oh My Zsh..."
        sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" "" --unattended
    fi
    
    # Set zsh as default shell if not already
    if [ "$SHELL" != "/usr/bin/zsh" ]; then
        print_status "Setting zsh as default shell..."
        chsh -s /usr/bin/zsh
    fi
    
    # Configure starship
    if [ ! -f ~/.config/starship.toml ]; then
        print_status "Creating default starship config..."
        mkdir -p ~/.config
        # Use a valid preset name
        starship preset bracketed-segments -o ~/.config/starship.toml || \
        cat > ~/.config/starship.toml << 'EOF'
# Starship configuration
format = """
[░▒▓](#a3aed2)\
[  ](bg:#a3aed2 fg:#090c0c)\
[](bg:#769ff0 fg:#a3aed2)\
$directory\
[](fg:#769ff0 bg:#394260)\
$git_branch\
$git_status\
[](fg:#394260 bg:#212736)\
$nodejs\
$rust\
$golang\
$php\
[](fg:#212736 bg:#1d2230)\
$time\
[ ](fg:#1d2230)\
\n$character"""

[directory]
style = "fg:#e3e5e5 bg:#769ff0"
format = "[ $path ]($style)"
truncation_length = 3
truncation_symbol = "…/"

[git_branch]
symbol = ""
style = "fg:#e3e5e5 bg:#394260"
format = '[[ $symbol $branch ](fg:#e3e5e5 bg:#394260)]($style)'

[git_status]
style = "fg:#e3e5e5 bg:#394260"
format = '[[($all_status$ahead_behind )](fg:#e3e5e5 bg:#394260)]($style)'

[nodejs]
symbol = ""
style = "fg:#e3e5e5 bg:#212736"
format = '[[ $symbol ($version) ](fg:#e3e5e5 bg:#212736)]($style)'

[rust]
symbol = ""
style = "fg:#e3e5e5 bg:#212736"
format = '[[ $symbol ($version) ](fg:#e3e5e5 bg:#212736)]($style)'

[golang]
symbol = ""
style = "fg:#e3e5e5 bg:#212736"
format = '[[ $symbol ($version) ](fg:#e3e5e5 bg:#212736)]($style)'

[php]
symbol = ""
style = "fg:#e3e5e5 bg:#212736"
format = '[[ $symbol ($version) ](fg:#e3e5e5 bg:#212736)]($style)'

[time]
disabled = false
time_format = "%R"
style = "fg:#e3e5e5 bg:#1d2230"
format = '[[  $time ](fg:#e3e5e5 bg:#1d2230)]($style)'

[character]
success_symbol = '[➜](bold fg:#86e1fc)'
error_symbol = '[➜](bold fg:#ff757f)'
EOF
    fi
    
    # Add starship to bashrc and zshrc
    if ! grep -q "starship init bash" ~/.bashrc 2>/dev/null; then
        echo 'eval "$(starship init bash)"' >> ~/.bashrc
    fi
    
    if ! grep -q "starship init zsh" ~/.zshrc 2>/dev/null; then
        echo 'eval "$(starship init zsh)"' >> ~/.zshrc
    fi
    
    print_success "Shell configured!"
}

# Configure GTK themes
configure_gtk_themes() {
    print_status "Configuring GTK themes..."
    
    # GTK 3 settings
    mkdir -p ~/.config/gtk-3.0
    cat > ~/.config/gtk-3.0/settings.ini << EOF
[Settings]
gtk-theme-name=Catppuccin-Mocha-Standard-Flamingo-Dark
gtk-icon-theme-name=Papirus-Dark
gtk-font-name=Noto Sans 11
gtk-cursor-theme-name=Catppuccin-Mocha-Dark-Cursors
gtk-cursor-theme-size=24
gtk-toolbar-style=GTK_TOOLBAR_BOTH
gtk-toolbar-icon-size=GTK_ICON_SIZE_LARGE_TOOLBAR
gtk-button-images=1
gtk-menu-images=1
gtk-enable-event-sounds=0
gtk-enable-input-feedback-sounds=0
gtk-xft-antialias=1
gtk-xft-hinting=1
gtk-xft-hintstyle=hintfull
gtk-xft-rgba=rgb
gtk-application-prefer-dark-theme=1
EOF
    
    # GTK 4 settings
    mkdir -p ~/.config/gtk-4.0
    cat > ~/.config/gtk-4.0/settings.ini << EOF
[Settings]
gtk-theme-name=Catppuccin-Mocha-Standard-Flamingo-Dark
gtk-icon-theme-name=Papirus-Dark
gtk-font-name=Noto Sans 11
gtk-cursor-theme-name=Catppuccin-Mocha-Dark-Cursors
gtk-cursor-theme-size=24
gtk-application-prefer-dark-theme=1
EOF
    
    print_success "GTK themes configured!"
}

# Create default Hyprland config if dotfiles don't provide one
create_default_hyprland_config() {
    if [ ! -f ~/.config/hypr/hyprland.conf ]; then
        print_status "Creating default Hyprland configuration..."
        mkdir -p ~/.config/hypr
        
        cat > ~/.config/hypr/hyprland.conf << 'EOF'
# Monitor configuration
monitor=,preferred,auto,1.6

# Execute at launch
exec-once = waybar
exec-once = hyprpaper
exec-once = swaync
exec-once = hypridle
exec-once = /usr/lib/polkit-gnome/polkit-gnome-authentication-agent-1
exec-once = wl-paste --type text --watch cliphist store
exec-once = wl-paste --type image --watch cliphist store

# Source color scheme
source = ~/.config/hypr/mocha.conf

# Environment variables
env = XCURSOR_SIZE,24
env = QT_QPA_PLATFORMTHEME,qt5ct

# Input configuration
input {
    kb_layout = us
    follow_mouse = 1
    touchpad {
        natural_scroll = yes
    }
    sensitivity = 0
}

# General configuration
general {
    gaps_in = 5
    gaps_out = 10
    border_size = 2
    col.active_border = rgba(f5c2e7ee) rgba(cba6f7ee) 45deg
    col.inactive_border = rgba(595959aa)
    layout = dwindle
}

# Decoration
decoration {
    rounding = 10
    blur {
        enabled = true
        size = 3
        passes = 1
    }
    drop_shadow = yes
    shadow_range = 4
    shadow_render_power = 3
    col.shadow = rgba(1a1a1aee)
}

# Animations
animations {
    enabled = yes
    bezier = myBezier, 0.05, 0.9, 0.1, 1.05
    animation = windows, 1, 7, myBezier
    animation = windowsOut, 1, 7, default, popin 80%
    animation = border, 1, 10, default
    animation = borderangle, 1, 8, default
    animation = fade, 1, 7, default
    animation = workspaces, 1, 6, default
}

# Layout
dwindle {
    pseudotile = yes
    preserve_split = yes
}

master {
    new_is_master = true
}

# Gestures
gestures {
    workspace_swipe = on
}

# Key bindings
$mainMod = SUPER

# Program bindings
bind = $mainMod, RETURN, exec, kitty
bind = $mainMod, C, killactive,
bind = $mainMod, M, exit,
bind = $mainMod, E, exec, nautilus
bind = $mainMod, V, togglefloating,
bind = $mainMod, SPACE, exec, wofi --show drun
bind = $mainMod, P, pseudo,
bind = $mainMod, J, togglesplit,
bind = $mainMod SHIFT, L, exec, hyprlock

# Screenshot bindings
bind = , Print, exec, hyprshot -m window
bind = SHIFT, Print, exec, hyprshot -m region

# Move focus with mainMod + vim keys
bind = $mainMod, h, movefocus, l
bind = $mainMod, l, movefocus, r
bind = $mainMod, k, movefocus, u
bind = $mainMod, j, movefocus, d

# Switch workspaces
bind = $mainMod, 1, workspace, 1
bind = $mainMod, 2, workspace, 2
bind = $mainMod, 3, workspace, 3
bind = $mainMod, 4, workspace, 4
bind = $mainMod, 5, workspace, 5
bind = $mainMod, 6, workspace, 6
bind = $mainMod, 7, workspace, 7
bind = $mainMod, 8, workspace, 8
bind = $mainMod, 9, workspace, 9
bind = $mainMod, 0, workspace, 10

# Move active window to workspace
bind = $mainMod SHIFT, 1, movetoworkspace, 1
bind = $mainMod SHIFT, 2, movetoworkspace, 2
bind = $mainMod SHIFT, 3, movetoworkspace, 3
bind = $mainMod SHIFT, 4, movetoworkspace, 4
bind = $mainMod SHIFT, 5, movetoworkspace, 5
bind = $mainMod SHIFT, 6, movetoworkspace, 6
bind = $mainMod SHIFT, 7, movetoworkspace, 7
bind = $mainMod SHIFT, 8, movetoworkspace, 8
bind = $mainMod SHIFT, 9, movetoworkspace, 9
bind = $mainMod SHIFT, 0, movetoworkspace, 10

# Scroll through existing workspaces
bind = $mainMod, mouse_down, workspace, e+1
bind = $mainMod, mouse_up, workspace, e-1

# Move/resize windows with mouse
bindm = $mainMod, mouse:272, movewindow
bindm = $mainMod, mouse:273, resizewindow

# Volume controls
bind = , XF86AudioRaiseVolume, exec, pamixer -i 5
bind = , XF86AudioLowerVolume, exec, pamixer -d 5
bind = , XF86AudioMute, exec, pamixer -t

# Brightness controls
bind = , XF86MonBrightnessUp, exec, brightnessctl s +5%
bind = , XF86MonBrightnessDown, exec, brightnessctl s 5%-
EOF
        print_success "Default Hyprland configuration created!"
    fi
}

# Enable services
enable_services() {
    print_status "Enabling system services..."
    
    # Enable NetworkManager
    sudo systemctl enable --now NetworkManager
    
    # Enable Bluetooth
    sudo systemctl enable --now bluetooth
    
    # Enable display manager if one is installed
    if systemctl list-unit-files | grep -q "sddm.service"; then
        sudo systemctl enable sddm
    elif systemctl list-unit-files | grep -q "gdm.service"; then
        sudo systemctl enable gdm
    elif systemctl list-unit-files | grep -q "lightdm.service"; then
        sudo systemctl enable lightdm
    fi
    
    print_success "Services enabled!"
}

# Main installation function
main() {
    clear
    echo "============================================"
    echo "   Hyprland Automated Installation Script   "
    echo "============================================"
    echo ""
    print_warning "This script will install and configure Hyprland on Arch Linux"
    print_warning "It assumes a fresh minimal Arch installation"
    echo ""
    read -p "Do you want to continue? (y/N): " -n 1 -r
    echo ""
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        print_status "Installation cancelled"
        exit 0
    fi
    
    # Run installation steps
    check_root
    update_system
    install_yay
    install_essential_packages
    install_aur_packages
    create_directories
    setup_dotfiles
    configure_shell
    configure_gtk_themes
    create_default_hyprland_config
    enable_services
    
    echo ""
    echo "============================================"
    echo "        Installation Complete!              "
    echo "============================================"
    echo ""
    print_success "Hyprland has been successfully installed and configured!"
    echo ""
    print_status "Next steps:"
    echo "  1. Reboot your system: sudo reboot"
    echo "  2. Select Hyprland from your display manager"
    echo "  3. Press Super+Return to open terminal"
    echo "  4. Press Super+Space to open application launcher"
    echo ""
    print_status "Key bindings:"
    echo "  Super + Return    - Open terminal (kitty)"
    echo "  Super + Space     - Open launcher (wofi)"
    echo "  Super + E         - Open file manager"
    echo "  Super + C         - Close window"
    echo "  Super + M         - Exit Hyprland"
    echo "  Super + Shift + L - Lock screen"
    echo "  Super + h/j/k/l   - Move focus (vim keys)"
    echo "  Super + 1-9       - Switch workspace"
    echo "  Print             - Screenshot window"
    echo "  Shift + Print     - Screenshot region"
    echo ""
    print_warning "Your old configs (if any) have been backed up to ~/.config.backup.*"
    echo ""
    read -p "Would you like to reboot now? (y/N): " -n 1 -r
    echo ""
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        sudo reboot
    fi
}

# Run main function
main "$@"
