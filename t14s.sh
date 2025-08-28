#!/bin/bash

# Quick Arch Linux Installation Script for Lenovo T14S Gen 2 AMD
# Minimal input required - uses sensible defaults

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log() { echo -e "${GREEN}[$(date +'%H:%M:%S')] $1${NC}"; }
warn() { echo -e "${YELLOW}[WARNING] $1${NC}"; }
error() { echo -e "${RED}[ERROR] $1${NC}"; }
info() { echo -e "${BLUE}[INFO] $1${NC}"; }

# Check root
if [ "$EUID" -ne 0 ]; then
    error "Run as root: sudo $0"
    exit 1
fi

# Check UEFI
if [ ! -d "/sys/firmware/efi" ]; then
    error "UEFI boot required"
    exit 1
fi

echo -e "${BLUE}==================================${NC}"
echo -e "${BLUE} Quick Arch Install for T14S AMD${NC}"
echo -e "${BLUE}==================================${NC}"

# Set defaults
TARGET_DISK="/dev/nvme0n1"
HOSTNAME="mercury"
USERNAME="kdos"

# Show defaults and allow quick override
echo ""
info "Default settings:"
echo "  Target Disk: $TARGET_DISK"
echo "  Hostname: $HOSTNAME" 
echo "  Username: $USERNAME"
echo ""
echo -n "Use these defaults? [Y/n]: "
read use_defaults

if [[ "$use_defaults" =~ ^[Nn]$ ]]; then
    echo -n "Target disk [$TARGET_DISK]: "
    read custom_disk
    [ -n "$custom_disk" ] && TARGET_DISK="$custom_disk"
    
    echo -n "Hostname [$HOSTNAME]: "
    read custom_hostname
    [ -n "$custom_hostname" ] && HOSTNAME="$custom_hostname"
    
    echo -n "Username [$USERNAME]: "
    read custom_username
    [ -n "$custom_username" ] && USERNAME="$custom_username"
fi

# Validate disk exists
if [ ! -b "$TARGET_DISK" ]; then
    error "Disk $TARGET_DISK not found"
    lsblk -d -o NAME,SIZE,MODEL
    exit 1
fi

# Get passwords with better UI
get_password() {
    local prompt="$1"
    local var_name="$2"
    local attempts=0
    
    while [ $attempts -lt 3 ]; do
        echo ""
        echo -e "${BLUE}=== $prompt ===${NC}"
        echo -n -e "${YELLOW}Password: ${NC}"
        read -s pass1
        echo ""
        echo -n -e "${YELLOW}Confirm:  ${NC}"
        read -s pass2
        echo ""
        
        if [ "$pass1" = "$pass2" ]; then
            eval "$var_name=\"$pass1\""
            log "✓ Password set"
            return 0
        else
            error "✗ Passwords don't match"
            ((attempts++))
        fi
    done
    
    error "Too many failed attempts"
    exit 1
}

get_password "User Password" USER_PASSWORD
get_password "Disk Encryption Password" ENCRYPTION_PASSWORD

# Final confirmation
echo ""
warn "This will COMPLETELY WIPE $TARGET_DISK!"
echo -n "Continue? Type 'YES' to proceed: "
read final_confirm
if [ "$final_confirm" != "YES" ]; then
    log "Installation cancelled"
    exit 0
fi

# Start installation
log "Starting installation..."

# Clean up any existing setup
log "Cleaning up previous attempts..."
for mount in $(mount | grep /mnt | awk '{print $3}' | sort -r); do
    umount "$mount" 2>/dev/null || umount -f "$mount" 2>/dev/null || true
done

[ -e /dev/mapper/main ] && cryptsetup luksClose main 2>/dev/null || true

# Set timezone and update mirrors
log "Configuring time and mirrors..."
timedatectl set-timezone Australia/Melbourne
timedatectl set-ntp true

# Update mirrors quickly
if command -v reflector &> /dev/null; then
    reflector -c Australia -c "New Zealand" -f 10 --sort rate --save /etc/pacman.d/mirrorlist
fi

# Partition disk
log "Partitioning $TARGET_DISK..."
sgdisk --zap-all $TARGET_DISK
sgdisk --clear $TARGET_DISK
sgdisk --new=1:0:+1G --typecode=1:ef00 $TARGET_DISK
sgdisk --new=2:0:0 --typecode=2:8300 $TARGET_DISK
partprobe $TARGET_DISK
sleep 2

# Set partition variables
if [[ $TARGET_DISK == *"nvme"* ]]; then
    EFI_PARTITION="${TARGET_DISK}p1"
    ROOT_PARTITION="${TARGET_DISK}p2"
else
    EFI_PARTITION="${TARGET_DISK}1"
    ROOT_PARTITION="${TARGET_DISK}2"
fi

# Encryption
log "Setting up encryption..."
echo "$ENCRYPTION_PASSWORD" | cryptsetup luksFormat --type luks2 --pbkdf argon2id $ROOT_PARTITION -
echo "$ENCRYPTION_PASSWORD" | cryptsetup luksOpen $ROOT_PARTITION main -

# Filesystems
log "Creating filesystems..."
mkfs.fat -F32 $EFI_PARTITION
mkfs.btrfs -f /dev/mapper/main

# BTRFS subvolumes
log "Setting up BTRFS subvolumes..."
mount /dev/mapper/main /mnt
btrfs subvolume create /mnt/@
btrfs subvolume create /mnt/@home
umount /mnt

# Mount with optimized options
mount -o noatime,ssd,compress=zstd,space_cache=v2,discard=async,subvol=@ /dev/mapper/main /mnt
mkdir -p /mnt/home /mnt/boot
mount -o noatime,ssd,compress=zstd,space_cache=v2,discard=async,subvol=@home /dev/mapper/main /mnt/home
mount $EFI_PARTITION /mnt/boot

# Install base system
log "Installing base system (this may take a few minutes)..."
pacstrap /mnt base linux linux-headers linux-firmware

# Generate fstab
genfstab -U -p /mnt >> /mnt/etc/fstab

# Configure system
log "Configuring system..."
arch-chroot /mnt /bin/bash << CHROOT_END
# Timezone
ln -sf /usr/share/zoneinfo/Australia/Melbourne /etc/localtime
hwclock --systohc

# Install packages
pacman -S --noconfirm vim sudo base-devel btrfs-progs grub efibootmgr \
    networkmanager openssh git amd-ucode mesa man-db man-pages \
    firewalld reflector grub-btrfs xf86-video-amdgpu

# Locale
echo "en_AU.UTF-8 UTF-8" >> /etc/locale.gen
locale-gen
echo "LANG=en_AU.UTF-8" > /etc/locale.conf
echo "KEYMAP=us" > /etc/vconsole.conf

# Network
echo "$HOSTNAME" > /etc/hostname
echo "127.0.0.1 localhost" > /etc/hosts
echo "::1 localhost" >> /etc/hosts
echo "127.0.1.1 $HOSTNAME.localdomain $HOSTNAME" >> /etc/hosts

# Users
useradd -m -G wheel $USERNAME
echo "$USERNAME ALL=(ALL) ALL" > /etc/sudoers.d/$USERNAME

# Passwords
echo "root:$USER_PASSWORD" | chpasswd
echo "$USERNAME:$USER_PASSWORD" | chpasswd

# Initramfs
sed -i 's/^MODULES=()/MODULES=(btrfs)/' /etc/mkinitcpio.conf
sed -i 's/^HOOKS=(.*)/HOOKS=(base udev autodetect microcode modconf kms keyboard keymap consolefont block encrypt filesystems fsck)/' /etc/mkinitcpio.conf
mkinitcpio -p linux

# GRUB
grub-install --target=x86_64-efi --efi-directory=/boot --bootloader-id=grub
ROOT_UUID=\$(blkid -s UUID -o value $ROOT_PARTITION)
sed -i "s/^GRUB_CMDLINE_LINUX_DEFAULT=.*/GRUB_CMDLINE_LINUX_DEFAULT=\"loglevel=3 quiet cryptdevice=UUID=\$ROOT_UUID:main root=\/dev\/mapper\/main\"/" /etc/default/grub
sed -i 's/^#GRUB_ENABLE_CRYPTODISK=y/GRUB_ENABLE_CRYPTODISK=y/' /etc/default/grub
grub-mkconfig -o /boot/grub/grub.cfg

# Services
systemctl enable NetworkManager sshd firewalld reflector.timer fstrim.timer
CHROOT_END

log "✓ Installation completed successfully!"
echo ""
info "System Information:"
echo "  Hostname: $HOSTNAME"
echo "  User: $USERNAME"
echo "  Disk: $TARGET_DISK (encrypted BTRFS)"
echo ""
info "After reboot:"
echo "  1. Connect WiFi: nmcli dev wifi connect SSID --ask"
echo "  2. Update: sudo pacman -Syu"
echo ""

echo -n "Reboot now? [Y/n]: "
read reboot_now
if [[ ! "$reboot_now" =~ ^[Nn]$ ]]; then
    log "Rebooting in 3 seconds..."
    sleep 3
    reboot
fi
