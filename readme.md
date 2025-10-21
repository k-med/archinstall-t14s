# Hyprland Arch Setup — T14s & Generic Arch

A tiny repo with two Bash scripts:

- `t14s.sh` — **Hands-off Arch install** for a single-disk UEFI system (tested on ThinkPad T14s). Sets up LUKS2-encrypted **Btrfs** with `@` and `@home` subvols, installs base system, fixes common GRUB/UUID/initramfs pitfalls, and enables core services.
    
- `install-hyprland.sh` — **Post-install desktop bootstrap** for a fresh Arch user. Installs Hyprland + Wayland tooling, themes, fonts, shell (zsh + starship), clones dotfiles/wallpapers, stows configs, writes sane GTK settings, and enables network/bluetooth.
    

---

## Requirements

- Target distro: **Arch Linux** (fresh install expected).
    
- Firmware: **UEFI** (script checks `/sys/firmware/efi`).
    
- Internet access and `sudo` for the user phase.
    
- For `t14s.sh`: drive **will be wiped**. Back up first.
    

---

## Quick Start

```
# 0) Get the scripts
git clone <this-repo-url> arch-hypr-setup
cd arch-hypr-setup
chmod +x t14s.sh install-hyprland.sh
```

### A) Base system (as **root**, e.g. from the Arch ISO)

```
sudo ./t14s.sh
# Accept defaults or customize: disk, hostname, username.
# This creates LUKS2 on the root partition, Btrfs @/@home, installs base+grub,
# and enables NetworkManager, sshd, firewalld, reflector, fstrim.

```

Reboot into your new system and log in as the user you created.

### B) Desktop (as **normal user**, not root)

```
./install-hyprland.sh
# Installs Hyprland stack, waybar/wofi/swaync, pipewire, fonts/themes,
# oh-my-zsh + starship, clones dotfiles & wallpapers, stows configs,
# creates a default Hyprland config if dotfiles don’t provide one.

```

When it finishes:

- Reboot: `sudo reboot`
    
- Pick **Hyprland** in your display manager (if installed).
    
- First shortcuts:
    
    - **Super + Return**: kitty terminal
        
    - **Super + Space**: wofi launcher
        
    - **Super + E**: file manager
        
    - **Super + C**: close window
        
    - **Super + Shift + L**: lock
        
    - **Super + 1..0**: workspaces
        
    - **Print / Shift+Print**: screenshots
        

---

## What the scripts do

### `t14s.sh`

- Confirms UEFI and target disk, prompts for **user** and **encryption** passwords (kept in-memory).
    
- Partitions: `EFI (1GiB, FAT32)` + `root (LUKS2 -> Btrfs)`.
    
- Btrfs subvols: `@`, `@home`; mounts with `noatime,compress=zstd,...`.
    
- Installs: `base linux linux-headers linux-firmware` + essentials inside chroot (`btrfs-progs grub efibootmgr networkmanager openssh git amd-ucode mesa firewalld reflector grub-btrfs xf86-video-amdgpu`).
    
- Locale/timezone/hosts; creates user in `wheel`; sets passwords.
    
- mkinitcpio hooks for encryption + btrfs; enables `GRUB_ENABLE_CRYPTODISK=y`.
    
- Writes proper `GRUB_CMDLINE_LINUX_DEFAULT="... cryptdevice=UUID=<root>:main root=/dev/mapper/main"`, builds config.
    
- Enables: `NetworkManager`, `sshd`, `firewalld`, `reflector.timer`, `fstrim.timer`.
    

### `install-hyprland.sh`

- Refuses to run as root; updates system; installs **yay**.
    
- Installs core packages: Hyprland stack (hyprpaper/hypridle/hyprlock/hyprshot), waybar, wofi, swaync, pipewire/wireplumber, wl-clipboard/cliphist, grim/slurp, brightnessctl/pamixer/playerctl, Nautilus/Thunar, tty/fonts/themes, dev tools (git/stow/neovim), GTK/Qt theming.
    
- AUR: Catppuccin themes/cursors, Meslo Nerd Font, hyprpicker.
    
- Creates XDG dirs; clones:
    
    - `DOTFILES_REPO="https://github.com/maxhu08/dotfiles"`
        
    - `WALLPAPERS_REPO="https://github.com/maxhu08/wallpapers"`
        
- Backs up `~/.config` then `stow`s configs if present.
    
- Installs **oh-my-zsh** (unattended), sets **zsh** default, installs **starship** preset/fallback config, adds init lines to `.bashrc`/`.zshrc`.
    
- Writes GTK3/GTK4 Catppuccin settings.
    
- If no dotfile for Hyprland, writes a sensible default config (keybinds above).
    
- Enables `NetworkManager` & `bluetooth`; enables SDDM/GDM/LightDM if found.
    

---

## Customize

- Edit repo sources at the top of `install-hyprland.sh`:
    
    `DOTFILES_REPO="https://github.com/maxhu08/dotfiles" WALLPAPERS_REPO="https://github.com/maxhu08/wallpapers"`
    
- Swap file managers, terminals, themes, fonts by adjusting the package arrays.
    
- Hyprland defaults live in `~/.config/hypr/hyprland.conf` if no dotfiles.
    

---

## Notes & Warnings

- **Data loss**: `t14s.sh` wipes the target disk. Triple-check `TARGET_DISK`.
    
- Designed for **AMD iGPU** (packages include `amd-ucode`, `xf86-video-amdgpu`); adapt for Intel/NVIDIA if needed.
    
- Display manager is **optional**; you can start Hyprland from TTY if preferred.
    
- `install-hyprland.sh` backs up `~/.config` to `~/.config.backup.<timestamp>`.
    

---

## License

MIT — do whatever, no warranty. Use at your own risk.
