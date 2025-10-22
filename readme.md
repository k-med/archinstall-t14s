# 🚀 Hyprland Arch Setup — Automated Installation Scripts

Two automated Bash scripts to set up a beautiful, modern Arch Linux system with Hyprland (Wayland compositor):

1. **`t14s.sh`** — Complete Arch Linux base system installer
2. **`install-hyprland.sh`** — Desktop environment and application installer

Perfect for beginners who want a working Arch + Hyprland setup without manually typing hundreds of commands!

---

## 📸 What You'll Get

- **Modern Wayland desktop** with Hyprland window manager
- **Beautiful themes** (Catppuccin color scheme)
- **Complete toolset**: terminal, file manager, launcher, notifications
- **Encrypted system** with automatic snapshots (Btrfs)
- **Customizable** with pre-configured dotfiles

---

## ⚠️ Before You Start

### Important Warnings

**🔴 DATA LOSS WARNING**: The `t14s.sh` script will **completely erase** your target disk. Back up any important data first!

**💡 For New Users**: These scripts are designed for **ThinkPad T14s** with AMD graphics but work on most modern laptops. If you have NVIDIA or Intel graphics, you may need to modify some packages.

### What You Need

- A computer with **UEFI firmware** (not legacy BIOS)
- **8GB+ RAM** recommended
- **50GB+ free disk space** recommended
- **USB drive** with Arch Linux ISO (if doing fresh install)
- **Active internet connection** during installation
- **1-2 hours** for complete installation

---

## 📋 Installation Overview

```
┌─────────────────────────────────────────────────────────┐
│ Step 1: Boot Arch ISO → Run t14s.sh (Base System)      │
│ Step 2: Reboot & Login → Run install-hyprland.sh       │
│ Step 3: Reboot → Enjoy Hyprland Desktop!                │
└─────────────────────────────────────────────────────────┘
```

---

## 🎯 Step-by-Step Instructions

### Prerequisites: Creating a Bootable USB

1. **Download Arch Linux ISO**: Visit [archlinux.org/download](https://archlinux.org/download/)
2. **Create bootable USB**:
   - **Windows**: Use [Rufus](https://rufus.ie/)
   - **macOS/Linux**: Use `dd` command or [Etcher](https://etcher.balena.io/)
3. **Boot from USB**: Restart your computer and select the USB drive from boot menu (usually F12, F2, or DEL key)

### Step 1: Install Base System (Run from Arch ISO)

Once you've booted into the Arch Linux ISO, you'll see a terminal. Follow these steps:

```bash
# 1. Connect to WiFi (if needed)
iwctl                                    # Enter WiFi configuration tool
station wlan0 scan                       # Scan for networks
station wlan0 get-networks              # Show available networks
station wlan0 connect "YOUR_WIFI_NAME"  # Connect (will prompt for password)
exit                                     # Exit iwctl

# 2. Verify internet connection
ping -c 3 archlinux.org                 # Should see replies

# 3. Download the installation scripts
curl -LO https://raw.githubusercontent.com/k-med/archinstall-t14s/main/t14s.sh
curl -LO https://raw.githubusercontent.com/k-med/archinstall-t14s/main/install-hyprland.sh

# OR clone the repository
git clone https://github.com/k-med/archinstall-t14s.git
cd k-med

# 4. Make scripts executable
chmod +x t14s.sh install-hyprland.sh

# 5. Run the base system installer
sudo ./t14s.sh
```

#### What `t14s.sh` Does

The script will ask you to configure:

- **Target Disk** (default: `/dev/nvme0n1`) — ⚠️ This disk will be erased!
- **Hostname** (default: `mercury`) — Your computer's name
- **Username** (default: `kdos`) — Your login username
- **User Password** — Password for your user account
- **Encryption Password** — Password to unlock your encrypted disk

The script then:
- ✅ Partitions your disk (1GB EFI + remaining space for root)
- ✅ Sets up LUKS2 encryption for security
- ✅ Creates Btrfs filesystem with snapshots capability
- ✅ Installs Arch Linux base system
- ✅ Configures GRUB bootloader
- ✅ Enables essential services (NetworkManager, SSH, firewall)

**Time required**: ~20-40 minutes depending on internet speed

When finished, the script will ask if you want to reboot. Type `Y` and press Enter.

---

### Step 2: Install Desktop Environment

After rebooting:

1. You'll see a GRUB menu — press Enter to boot
2. **IMPORTANT**: You'll be prompted for your **encryption password** (the second password you set)
3. Log in with your **username** and **user password**

Now install the desktop environment:

```bash
# 1. Navigate to where you downloaded the scripts
cd ~                                    # Go to home directory

# If you need to download the script again:
curl -LO https://raw.githubusercontent.com/YOUR_USERNAME/YOUR_REPO/main/install-hyprland.sh
chmod +x install-hyprland.sh

# 2. Run the Hyprland installer (do NOT use sudo!)
./install-hyprland.sh
```

#### What `install-hyprland.sh` Does

The script will:
- ✅ Install Hyprland and Wayland tools
- ✅ Install desktop applications (terminal, file manager, launcher)
- ✅ Install fonts, themes, and icons (Catppuccin theme)
- ✅ Install audio system (Pipewire)
- ✅ Set up zsh shell with Oh My Zsh and Starship prompt
- ✅ Clone your dotfiles and wallpapers
- ✅ Configure everything automatically

**Time required**: ~30-60 minutes depending on internet speed

When complete, reboot your system:

```bash
sudo reboot
```

---

### Step 3: First Login to Hyprland

After rebooting:

1. Enter your **encryption password** at the GRUB prompt
2. You'll see a login screen (if display manager is installed) or TTY
3. Log in with your username and password
4. If using TTY, type: `Hyprland`

**🎉 Welcome to your new desktop!**

---

## ⌨️ Essential Keyboard Shortcuts

The **Super** key is the Windows key / Command key on your keyboard.

### Getting Started
- **Super + Return** — Open terminal (Kitty)
- **Super + Space** — Open application launcher (Wofi)
- **Super + E** — Open file manager (Nautilus)
- **Super + C** — Close current window
- **Super + Q** — Quit Hyprland

### Window Management
- **Super + H/J/K/L** — Move focus (Vim-style: left/down/up/right)
- **Super + V** — Toggle floating mode for current window
- **Super + P** — Toggle pseudo-tiling
- **Super + Mouse drag** — Move window
- **Super + Right Mouse** — Resize window

### Workspaces
- **Super + 1-9** — Switch to workspace 1-9
- **Super + Shift + 1-9** — Move window to workspace
- **Super + Mouse scroll** — Cycle through workspaces

### System Controls
- **Super + Shift + L** — Lock screen
- **Print Screen** — Screenshot current window
- **Shift + Print Screen** — Screenshot selected region
- **Volume Up/Down keys** — Adjust volume
- **Brightness Up/Down keys** — Adjust screen brightness

---

## 🎨 Customization

### Change Wallpaper

```bash
# Edit hyprpaper config
nvim ~/.config/hypr/hyprpaper.conf

# Change the wallpaper path
preload = ~/Pictures/Wallpapers/maxhu08/your-image.jpg
wallpaper = ,~/Pictures/Wallpapers/maxhu08/your-image.jpg
```

### Use Your Own Dotfiles

Edit the script before running:

```bash
nvim install-hyprland.sh

# Change these lines near the top:
DOTFILES_REPO="https://github.com/YOUR_USERNAME/YOUR_DOTFILES"
WALLPAPERS_REPO="https://github.com/YOUR_USERNAME/YOUR_WALLPAPERS"
```

### Modify Hyprland Configuration

```bash
nvim ~/.config/hypr/hyprland.conf
```

After making changes, reload Hyprland: **Super + Shift + R** (if configured) or restart Hyprland.

---

## 🔧 Common Issues & Solutions

### "Cannot find /dev/nvme0n1"

Your disk might have a different name. Check available disks:

```bash
lsblk
```

Common disk names:
- `/dev/nvme0n1` — NVMe SSD
- `/dev/sda` — SATA SSD/HDD
- `/dev/vda` — Virtual machine disk

Edit the script and change `TARGET_DISK` before running.

### "Not booting with UEFI"

Your system must support UEFI. Check with:

```bash
ls /sys/firmware/efi
```

If this directory doesn't exist, your system uses legacy BIOS (not supported by these scripts).

### WiFi Not Working After Install

```bash
# Enable NetworkManager
sudo systemctl enable --now NetworkManager

# Connect to WiFi
nmcli device wifi list                    # List networks
nmcli device wifi connect "SSID" password "PASSWORD"
```

### Display Manager Not Starting

If you prefer to start Hyprland from TTY (terminal login):

```bash
# Log in at TTY
# Type:
Hyprland
```

### Audio Not Working

```bash
# Check if pipewire is running
systemctl --user status pipewire pipewire-pulse

# Restart audio services
systemctl --user restart pipewire pipewire-pulse wireplumber
```

### Screen Tearing or Graphics Issues

For NVIDIA users, you'll need additional configuration. The script is optimized for AMD/Intel graphics.

---

## 📦 Installed Software

### Core System
- **Window Manager**: Hyprland (Wayland compositor)
- **Terminal**: Kitty
- **Shell**: Zsh with Oh My Zsh
- **Prompt**: Starship
- **Launcher**: Wofi
- **Status Bar**: Waybar
- **Notifications**: SwayNC
- **File Manager**: Nautilus, Thunar
- **Editor**: Neovim

### Utilities
- **Screenshots**: Hyprshot, Grim, Slurp
- **Clipboard**: wl-clipboard, cliphist
- **Wallpaper**: Hyprpaper
- **Lock Screen**: Hyprlock
- **Idle Management**: Hypridle
- **Color Picker**: Hyprpicker
- **Brightness**: brightnessctl
- **Volume**: pamixer
- **Media**: playerctl

### Themes & Fonts
- **GTK Theme**: Catppuccin Mocha
- **Cursors**: Catppuccin Mocha Dark
- **Icons**: Papirus Dark
- **Fonts**: Cascadia Code Nerd Font, Meslo Nerd Font, Font Awesome, Noto Fonts

---

## 🤝 Contributing

Found a bug? Want to improve the scripts? Contributions welcome!

1. Fork this repository
2. Make your changes
3. Test thoroughly
4. Submit a pull request

---

## 📚 Additional Resources

### Learn More About:
- **Arch Linux**: [Arch Wiki](https://wiki.archlinux.org/)
- **Hyprland**: [Hyprland Wiki](https://wiki.hyprland.org/)
- **Wayland**: [Wayland Documentation](https://wayland.freedesktop.org/)
- **Btrfs**: [Btrfs Wiki](https://btrfs.wiki.kernel.org/)

### Getting Help
- [Arch Linux Forums](https://bbs.archlinux.org/)
- [Hyprland Discord](https://discord.gg/hQ9XvMUjjr)
- [r/archlinux](https://reddit.com/r/archlinux)
- [r/hyprland](https://reddit.com/r/hyprland)

---

## ⚖️ License

MIT License — Use freely, modify as needed, no warranty provided.

---

## 🙏 Credits

- Scripts based on tutorials and configurations from the Linux community
- Dotfiles: [maxhu08/dotfiles](https://github.com/maxhu08/dotfiles)
- Themes: Catppuccin project
- Hyprland: Hyprland development team

---

## 💡 Tips for Success

1. **Read the warnings** — Especially about data loss
2. **Have internet connection** — Both scripts download packages
3. **Be patient** — Installation takes time, don't interrupt
4. **Take notes** — Write down your passwords!
5. **Backup first** — Can't stress this enough
6. **Start simple** — Use default settings first, customize later
7. **Join communities** — Linux community is helpful!

**Good luck with your Arch + Hyprland setup! 🚀**
