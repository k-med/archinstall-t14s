#!/bin/bash

# Arch Linux Automated Installation Script
# Based on T14s Gen 2 AMD installation notes

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Global variables
TARGET_DISK=""
HOSTNAME=""
USERNAME=""
ROOT_PASSWORD=""
USER_PASSWORD=""
ENCRYPTION_PASSWORD=""
WIFI_SSID=""
WIFI_PASSWORD=""

print_status() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

print_header() {
    echo -e "${BLUE}================================${NC}"
    echo -e "${BLUE}$1${NC}"
    echo -e "${BLUE}================================${NC}"
}

pause_for_user() {
    echo -e "${YELLOW}Press Enter to continue...${NC}"
    read
}

# Function to get user inputs
get_user_inputs() {
    print_header "SYSTEM CONFIGURATION"
    
    # Hostname
    while [[ -z "$HOSTNAME" ]]; do
        read -p "Enter hostname (e.g., mercury): " HOSTNAME
    done
    
    # Username
    while [[ -z "$USERNAME" ]]; do
        read -p "Enter username: " USERNAME
    done
    
    # Passwords
    while [[ -z "$ROOT_PASSWORD" ]]; do
        read -s -p "Enter root password: " ROOT_PASSWORD
        echo
    done
    
    while [[ -z "$USER_PASSWORD" ]]; do
        read -s -p "Enter user password: " USER_PASSWORD
        echo
    done
    
    while [[ -z "$ENCRYPTION_PASSWORD" ]]; do
        read -s -p "Enter disk encryption password: " ENCRYPTION_PASSWORD
        echo
    done
    
    print_status "Configuration saved!"
}

# Function to connect to WiFi
setup_wifi() {
    print_header "WIFI SETUP"
    
    print_status "Available WiFi networks:"
    iwctl station wlan0 scan
    sleep 2
    iwctl station wlan0 get-networks
    
    read -p "Enter WiFi SSID: " WIFI_SSID
    read -s -p "Enter WiFi Password: " WIFI_PASSWORD
    echo
    
    print_status "Connecting to WiFi..."
    iwctl --passphrase="$WIFI_PASSWORD" station wlan0 connect "$WIFI_SSID"
    
    sleep 3
    if ping -c 3 google.com &> /dev/null; then
        print_status "Internet connection successful!"
    else
        print_error "Failed to connect to internet. Please check your credentials."
        exit 1
    fi
}

# Function to setup system basics
setup_system_basics() {
    print_header "SYSTEM BASICS SETUP"
    
    print_status "Setting keymap to US..."
    loadkeys us
    
    print_status "Checking UEFI boot mode..."
    if [[ ! -f /sys/firmware/efi/fw_platform_size ]]; then
        print_error "System is not booted in UEFI mode!"
        exit 1
    fi
    
    print_status "Setting timezone to Australia/Melbourne..."
    timedatectl set-timezone Australia/Melbourne
    timedatectl set-ntp true
    
    print_status "System basics configured!"
}

# Function to select and partition disk
partition_disk() {
    print_header "DISK PARTITIONING"
    
    print_status "Available disks:"
    lsblk -d -o NAME,SIZE,MODEL
    
    while [[ -z "$TARGET_DISK" ]]; do
        read -p "Enter target disk (e.g., nvme0n1): " TARGET_DISK
        if [[ ! -b "/dev/$TARGET_DISK" ]]; then
            print_error "Disk /dev/$TARGET_DISK does not exist!"
            TARGET_DISK=""
        fi
    done
    
    print_warning "This will COMPLETELY ERASE /dev/$TARGET_DISK!"
    read -p "Are you sure? (yes/no): " confirm
    if [[ "$confirm" != "yes" ]]; then
        print_error "Aborted by user"
        exit 1
    fi
    
    print_status "Partitioning /dev/$TARGET_DISK..."
    
    # Create GPT partition table and partitions
    sgdisk -Z "/dev/$TARGET_DISK"
    sgdisk -n 1:0:+1G -t 1:ef00 -c 1:"EFI System" "/dev/$TARGET_DISK"
    sgdisk -n 2:0:0 -t 2:8300 -c 2:"Linux filesystem" "/dev/$TARGET_DISK"
    
    # Wait for kernel to recognize partitions
    sleep 2
    partprobe "/dev/$TARGET_DISK"
    
    print_status "Partitioning complete!"
    lsblk "/dev/$TARGET_DISK"
}

# Function to setup encryption and filesystems
setup_encryption_and_filesystems() {
    print_header "ENCRYPTION AND FILESYSTEM SETUP"
    
    print_status "Setting up LUKS encryption on /dev/${TARGET_DISK}p2..."
    echo -n "$ENCRYPTION_PASSWORD" | cryptsetup luksFormat "/dev/${TARGET_DISK}p2" -
    echo -n "$ENCRYPTION_PASSWORD" | cryptsetup luksOpen "/dev/${TARGET_DISK}p2" main -
    
    print_status "Creating Btrfs filesystem..."
    mkfs.btrfs /dev/mapper/main
    
    print_status "Creating and mounting Btrfs subvolumes..."
    mount /dev/mapper/main /mnt
    cd /mnt
    btrfs subvolume create @
    btrfs subvolume create @home
    cd /
    umount /mnt
    
    # Mount with optimized options
    mount -o noatime,ssd,compress=zstd,space_cache=v2,discard=async,subvol=@ /dev/mapper/main /mnt
    mkdir /mnt/home
    mount -o noatime,ssd,compress=zstd,space_cache=v2,discard=async,subvol=@home /dev/mapper/main /mnt/home
    
    print_status "Setting up EFI partition..."
    mkfs.fat -F32 "/dev/${TARGET_DISK}p1"
    mkdir /mnt/boot
    mount "/dev/${TARGET_DISK}p1" /mnt/boot
    
    print_status "Filesystem setup complete!"
}

# Function to update mirrorlist
update_mirrors() {
    print_header "UPDATING MIRRORS"
    
    print_status "Updating pacman mirrorlist for Australia..."
    # Fallback method if reflector fails
    if ! reflector -c Australia -a 12 --sort rate --save /etc/pacman.d/mirrorlist; then
        print_warning "Reflector failed, using manual method..."
        curl -s "https://archlinux.org/mirrorlist/?country=AU&protocol=https&use_mirror_status=on" | \
        sed -e 's/^#Server/Server/' -e '/^#/d' > /etc/pacman.d/mirrorlist
    fi
    
    print_status "Mirrors updated!"
}

# Function to install base system
install_base_system() {
    print_header "INSTALLING BASE SYSTEM"
    
    print_status "Installing base packages..."
    pacstrap /mnt base linux linux-headers linux-firmware
    
    print_status "Generating fstab..."
    genfstab -U -p /mnt >> /mnt/etc/fstab
    
    print_status "Base system installed!"
}

# Function to configure system in chroot
configure_system() {
    print_header "CONFIGURING SYSTEM"
    
    print_status "Entering chroot and configuring system..."
    
    # Create configuration script to run in chroot
    cat > /mnt/configure_system.sh << EOF
#!/bin/bash
set -e

# Set timezone
ln -sf /usr/share/zoneinfo/Australia/Melbourne /etc/localtime
hwclock --systohc

# Install essential packages
pacman -S --noconfirm vim sudo base-devel btrfs-progs grub efibootmgr mtools \
networkmanager network-manager-applet openssh git iptables-nft ipset firewalld \
acpid reflector grub-btrfs amd-ucode mesa xf86-video-amdgpu man-db man-pages

# Configure locale
echo "en_AU.UTF-8 UTF-8" >> /etc/locale.gen
locale-gen
echo "LANG=en_AU.UTF-8" > /etc/locale.conf
echo "KEYMAP=us" > /etc/vconsole.conf

# Set hostname
echo "$HOSTNAME" > /etc/hostname

# Set root password
echo "root:$ROOT_PASSWORD" | chpasswd

# Create user
useradd -m -g users -G wheel "$USERNAME"
echo "$USERNAME:$USER_PASSWORD" | chpasswd

# Configure sudo
echo "$USERNAME ALL=(ALL) ALL" > /etc/sudoers.d/$USERNAME

# Configure mkinitcpio for encryption
sed -i 's/^MODULES=.*/MODULES=(btrfs)/' /etc/mkinitcpio.conf
sed -i 's/^HOOKS=.*/HOOKS=(base udev autodetect microcode modconf kms keyboard keymap consolefont block encrypt filesystems fsck)/' /etc/mkinitcpio.conf
mkinitcpio -p linux

# Install and configure GRUB
grub-install --target=x86_64-efi --efi-directory=/boot --bootloader-id=grub

# Get UUID for encryption
UUID=\$(blkid -s UUID -o value /dev/${TARGET_DISK}p2)

# Configure GRUB for encryption
sed -i "s/^GRUB_CMDLINE_LINUX_DEFAULT=.*/GRUB_CMDLINE_LINUX_DEFAULT=\"loglevel=3 quiet cryptdevice=UUID=\$UUID:main root=\/dev\/mapper\/main\"/" /etc/default/grub

# Generate GRUB config
grub-mkconfig -o /boot/grub/grub.cfg

# Enable services
systemctl enable NetworkManager
systemctl enable sshd
systemctl enable firewalld
systemctl enable reflector.timer
systemctl enable fstrim.timer
systemctl enable acpid

echo "System configuration complete!"
EOF
    
    # Make script executable and run in chroot
    chmod +x /mnt/configure_system.sh
    arch-chroot /mnt /configure_system.sh
    
    # Clean up
    rm /mnt/configure_system.sh
    
    print_status "System configuration complete!"
}

# Function to complete installation
complete_installation() {
    print_header "INSTALLATION COMPLETE"
    
    print_status "Installation has been completed successfully!"
    echo
    echo -e "${GREEN}System Details:${NC}"
    echo "  Hostname: $HOSTNAME"
    echo "  Username: $USERNAME"
    echo "  Disk: /dev/$TARGET_DISK"
    echo "  Filesystem: Btrfs with LUKS encryption"
    echo
    print_warning "The system will now reboot."
    print_warning "After reboot, connect to WiFi with: nmcli device wifi connect SSID --ask"
    echo
    
    read -p "Reboot now? (y/n): " reboot_choice
    if [[ "$reboot_choice" =~ ^[Yy]$ ]]; then
        umount -R /mnt
        reboot
    else
        print_status "You can manually reboot with: umount -R /mnt && reboot"
    fi
}

# Main installation function
main() {
    print_header "ARCH LINUX AUTOMATED INSTALLER"
    print_warning "This script will install Arch Linux with LUKS encryption and Btrfs"
    pause_for_user
    
    get_user_inputs
    setup_wifi
    setup_system_basics
    partition_disk
    setup_encryption_and_filesystems
    update_mirrors
    install_base_system
    configure_system
    complete_installation
}

# Check if running as root
if [[ $EUID -ne 0 ]]; then
   print_error "This script must be run as root (you're already root in the Arch ISO)"
   exit 1
fi

# Check if running in Arch ISO environment
if [[ ! -f /etc/arch-release ]]; then
    print_error "This script should be run from an Arch Linux live environment"
    exit 1
fi

# Run main installation
main