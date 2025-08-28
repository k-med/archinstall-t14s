#!/bin/bash

# Arch Linux Installation Script for Lenovo T14S Gen 2 AMD
# Based on custom installation notes with BTRFS, encryption, and optimizations

set -e  # Exit on any error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging function
log() {
    echo -e "${GREEN}[$(date +'%H:%M:%S')] $1${NC}"
}

warn() {
    echo -e "${YELLOW}[WARNING] $1${NC}"
}

error() {
    echo -e "${RED}[ERROR] $1${NC}"
}

info() {
    echo -e "${BLUE}[INFO] $1${NC}"
}

# Check if running as root
if [ "$EUID" -ne 0 ]; then
    error "This script must be run as root (use sudo or run from root account)"
    exit 1
fi

# Check for UEFI
if [ ! -d "/sys/firmware/efi" ]; then
    error "This script requires UEFI boot mode. Legacy BIOS is not supported."
    exit 1
fi

echo -e "${BLUE}=================================${NC}"
echo -e "${BLUE} Arch Linux Installation Script${NC}"
echo -e "${BLUE} Lenovo T14S Gen 2 AMD Optimized${NC}"
echo -e "${BLUE}=================================${NC}"
echo ""

# Function to get user input with validation
get_input() {
    local prompt="$1"
    local var_name="$2"
    local validation_func="$3"
    local value

    while true; do
        echo -n -e "${YELLOW}$prompt: ${NC}"
        read value
        if [ -z "$validation_func" ] || $validation_func "$value"; then
            eval "$var_name=\"$value\""
            break
        fi
    done
}

# Validation functions
validate_hostname() {
    if [[ "$1" =~ ^[a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?$ ]]; then
        return 0
    else
        error "Invalid hostname. Use only letters, numbers, and hyphens."
        return 1
    fi
}

validate_username() {
    if [[ "$1" =~ ^[a-z_]([a-z0-9_-]{0,31}|[a-z0-9_-]{0,30}\$)$ ]]; then
        return 0
    else
        error "Invalid username. Use lowercase letters, numbers, underscores, and hyphens."
        return 1
    fi
}

validate_disk() {
    if [ -b "$1" ]; then
        return 0
    else
        error "Disk $1 does not exist."
        return 1
    fi
}

# Function to securely get password with confirmation
get_password() {
    local prompt="$1"
    local var_name="$2"
    local password1
    local password2

    while true; do
        echo -n -e "${YELLOW}$prompt: ${NC}"
        read -s password1
        echo ""
        echo -n -e "${YELLOW}Confirm $prompt: ${NC}"
        read -s password2
        echo ""

        if [ "$password1" = "$password2" ]; then
            if [ ${#password1} -lt 8 ]; then
                warn "Password should be at least 8 characters long for security."
                echo -n "Continue with this password? [y/N]: "
                read confirm
                if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
                    continue
                fi
            fi
            eval "$var_name=\"$password1\""
            break
        else
            error "Passwords do not match. Please try again."
        fi
    done
}

# Display available disks
log "Available disks:"
lsblk -d -o NAME,SIZE,MODEL | grep -E "nvme|sd"

echo ""
get_input "Enter target disk (e.g., /dev/nvme0n1)" TARGET_DISK validate_disk
get_input "Enter hostname" HOSTNAME validate_hostname
get_input "Enter username" USERNAME validate_username

get_password "Enter user password" USER_PASSWORD
get_password "Enter disk encryption password (can be very long)" ENCRYPTION_PASSWORD

# Confirm settings
echo ""
info "Installation Settings:"
echo "Target Disk: $TARGET_DISK"
echo "Hostname: $HOSTNAME"
echo "Username: $USERNAME"
echo ""
warn "WARNING: This will completely wipe $TARGET_DISK!"
echo -n "Continue? [y/N]: "
read confirm
if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
    log "Installation cancelled."
    exit 0
fi

# Set up time and timezone
log "Setting up timezone and time sync..."
timedatectl set-timezone Australia/Melbourne
timedatectl set-ntp true

# Update mirrorlist
log "Updating mirror list for Australia/New Zealand..."
if command -v reflector &> /dev/null; then
    reflector -c Australia -c "New Zealand" -a 12 --sort rate --save /etc/pacman.d/mirrorlist
else
    warn "Reflector not available, using manual mirror setup..."
    curl -s "https://archlinux.org/mirrorlist/?country=AU&protocol=https&use_mirror_status=on" | sed -e 's/^#Server/Server/' -e '/^#/d' > /etc/pacman.d/mirrorlist
fi

# Partition the disk
log "Partitioning $TARGET_DISK..."
sgdisk --zap-all $TARGET_DISK
sgdisk --clear $TARGET_DISK
sgdisk --new=1:0:+1G --typecode=1:ef00 --change-name=1:"EFI System" $TARGET_DISK
sgdisk --new=2:0:0 --typecode=2:8300 --change-name=2:"Linux filesystem" $TARGET_DISK

# Get partition names
if [[ $TARGET_DISK == *"nvme"* ]]; then
    EFI_PARTITION="${TARGET_DISK}p1"
    ROOT_PARTITION="${TARGET_DISK}p2"
else
    EFI_PARTITION="${TARGET_DISK}1"
    ROOT_PARTITION="${TARGET_DISK}2"
fi

log "EFI Partition: $EFI_PARTITION"
log "Root Partition: $ROOT_PARTITION"

# Set up encryption
log "Setting up disk encryption..."
echo "$ENCRYPTION_PASSWORD" | cryptsetup luksFormat --type luks2 $ROOT_PARTITION -
echo "$ENCRYPTION_PASSWORD" | cryptsetup luksOpen $ROOT_PARTITION main -

# Format filesystems
log "Creating filesystems..."
mkfs.fat -F32 $EFI_PARTITION
mkfs.btrfs /dev/mapper/main

# Mount and create BTRFS subvolumes
log "Setting up BTRFS subvolumes..."
mount /dev/mapper/main /mnt
cd /mnt
btrfs subvolume create @
btrfs subvolume create @home
cd /
umount /mnt

# Mount with optimized options
log "Mounting filesystems with optimized options..."
mount -o noatime,ssd,compress=zstd,space_cache=v2,discard=async,subvol=@ /dev/mapper/main /mnt
mkdir -p /mnt/home
mount -o noatime,ssd,compress=zstd,space_cache=v2,discard=async,subvol=@home /dev/mapper/main /mnt/home
mkdir -p /mnt/boot
mount $EFI_PARTITION /mnt/boot

# Install base system
log "Installing base system..."
pacstrap /mnt base linux linux-headers linux-firmware

# Generate fstab
log "Generating fstab..."
genfstab -U -p /mnt >> /mnt/etc/fstab

# Create configuration script for chroot
log "Creating chroot configuration script..."
cat > /mnt/configure_system.sh << 'CHROOT_EOF'
#!/bin/bash

# Set timezone
ln -sf /usr/share/zoneinfo/Australia/Melbourne /etc/localtime
hwclock --systohc

# Install essential packages
pacman -S --noconfirm vim sudo base-devel btrfs-progs grub efibootmgr mtools \
    networkmanager network-manager-applet openssh git iptables-nft ipset \
    firewalld acpid reflector grub-btrfs amd-ucode mesa xf86-video-amdgpu \
    man-db man-pages

# Set locale
echo "en_AU.UTF-8 UTF-8" >> /etc/locale.gen
locale-gen
echo "LANG=en_AU.UTF-8" > /etc/locale.conf
echo "KEYMAP=us" > /etc/vconsole.conf

# Set hostname
echo "PLACEHOLDER_HOSTNAME" > /etc/hostname
echo "127.0.0.1 localhost" >> /etc/hosts
echo "::1 localhost" >> /etc/hosts
echo "127.0.1.1 PLACEHOLDER_HOSTNAME.localdomain PLACEHOLDER_HOSTNAME" >> /etc/hosts

# Create user
useradd -m -g users -G wheel PLACEHOLDER_USERNAME
echo "PLACEHOLDER_USERNAME ALL=(ALL) ALL" > /etc/sudoers.d/PLACEHOLDER_USERNAME

# Configure mkinitcpio for encryption and BTRFS
sed -i 's/^MODULES=()/MODULES=(btrfs)/' /etc/mkinitcpio.conf
sed -i 's/^HOOKS=(.*)/HOOKS=(base udev autodetect microcode modconf kms keyboard keymap consolefont block encrypt filesystems fsck)/' /etc/mkinitcpio.conf
mkinitcpio -p linux

# Install and configure GRUB
grub-install --target=x86_64-efi --efi-directory=/boot --bootloader-id=grub

# Configure GRUB for encryption
ROOT_UUID=$(blkid -s UUID -o value PLACEHOLDER_ROOT_PARTITION)
sed -i "s/^GRUB_CMDLINE_LINUX_DEFAULT=.*/GRUB_CMDLINE_LINUX_DEFAULT=\"loglevel=3 quiet cryptdevice=UUID=$ROOT_UUID:main root=\/dev\/mapper\/main\"/" /etc/default/grub
sed -i 's/^#GRUB_ENABLE_CRYPTODISK=y/GRUB_ENABLE_CRYPTODISK=y/' /etc/default/grub

grub-mkconfig -o /boot/grub/grub.cfg

# Enable services
systemctl enable NetworkManager
systemctl enable sshd
systemctl enable firewalld
systemctl enable reflector.timer
systemctl enable fstrim.timer
systemctl enable acpid

echo "System configuration completed!"
CHROOT_EOF

# Replace placeholders in the chroot script
sed -i "s/PLACEHOLDER_HOSTNAME/$HOSTNAME/g" /mnt/configure_system.sh
sed -i "s/PLACEHOLDER_USERNAME/$USERNAME/g" /mnt/configure_system.sh
sed -i "s|PLACEHOLDER_ROOT_PARTITION|$ROOT_PARTITION|g" /mnt/configure_system.sh

chmod +x /mnt/configure_system.sh

# Set passwords in chroot
cat > /mnt/set_passwords.sh << CHROOT_PASS_EOF
#!/bin/bash
echo "root:$USER_PASSWORD" | chpasswd
echo "$USERNAME:$USER_PASSWORD" | chpasswd
CHROOT_PASS_EOF

chmod +x /mnt/set_passwords.sh

# Execute configuration in chroot
log "Configuring system in chroot environment..."
arch-chroot /mnt /configure_system.sh
arch-chroot /mnt /set_passwords.sh

# Clean up
rm /mnt/configure_system.sh /mnt/set_passwords.sh

log "Installation completed successfully!"
log "System is ready for reboot."

echo ""
info "Installation Summary:"
echo "- Hostname: $HOSTNAME"
echo "- User: $USERNAME"
echo "- Encrypted BTRFS root with optimized mount options"
echo "- AMD-optimized drivers installed"
echo "- Services enabled: NetworkManager, SSH, Firewall, Reflector, Trim, ACPID"
echo ""
warn "After reboot:"
echo "1. Connect to WiFi: nmcli device wifi connect SSID --ask"
echo "2. Update system: sudo pacman -Syu"
echo "3. Install additional packages as needed"
echo ""

echo -n "Reboot now? [y/N]: "
read reboot_confirm
if [[ "$reboot_confirm" =~ ^[Yy]$ ]]; then
    log "Rebooting in 3 seconds..."
    sleep 3
    reboot
else
    log "Reboot manually when ready: sudo reboot"
fi
