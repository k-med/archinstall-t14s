#!/bin/bash

# Fixed Arch Linux Installation Script
# Addresses the encryption password and GRUB UUID issues

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log() { echo -e "${GREEN}[$(date +'%H:%M:%S')] $1${NC}"; }
warn() { echo -e "${YELLOW}[WARNING] $1${NC}"; }
error() { echo -e "${RED}[ERROR] $1${NC}"; }
info() { echo -e "${BLUE}[INFO] $1${NC}"; }

if [ "$EUID" -ne 0 ]; then
    error "Run as root: sudo $0"
    exit 1
fi

if [ ! -d "/sys/firmware/efi" ]; then
    error "UEFI boot required"
    exit 1
fi

echo -e "${BLUE}================================${NC}"
echo -e "${BLUE} Fixed Arch Install for T14S${NC}"
echo -e "${BLUE}================================${NC}"

# Defaults
TARGET_DISK="/dev/nvme0n1"
HOSTNAME="mercury"
USERNAME="kdos"

echo ""
info "Default settings:"
echo "  Target Disk: $TARGET_DISK"
echo "  Hostname: $HOSTNAME" 
echo "  Username: $USERNAME"
echo ""
echo -n "Use defaults? [Y/n]: "
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

if [ ! -b "$TARGET_DISK" ]; then
    error "Disk $TARGET_DISK not found"
    lsblk -d -o NAME,SIZE,MODEL
    exit 1
fi

# Better password function using printf instead of echo
get_secure_password() {
    local prompt="$1"
    local var_name="$2"
    local password1
    local password2
    
    while true; do
        echo ""
        echo -e "${BLUE}=== $prompt ===${NC}"
        printf "${YELLOW}Enter password: ${NC}"
        read -s password1
        printf "\n${YELLOW}Confirm password: ${NC}"
        read -s password2
        printf "\n"
        
        if [ "$password1" = "$password2" ] && [ -n "$password1" ]; then
            # Store in a file temporarily for reliable passing to cryptsetup
            printf "%s" "$password1" > "/tmp/${var_name,,}_pass"
            chmod 600 "/tmp/${var_name,,}_pass"
            eval "$var_name=\"/tmp/${var_name,,}_pass\""
            log "✓ Password set (length: ${#password1})"
            break
        elif [ -z "$password1" ]; then
            error "Password cannot be empty"
        else
            error "Passwords don't match, try again"
        fi
    done
}

get_secure_password "User Password" USER_PASSWORD_FILE
get_secure_password "Disk Encryption Password" ENCRYPTION_PASSWORD_FILE

echo ""
warn "This will COMPLETELY WIPE $TARGET_DISK!"
echo -n "Type 'YES' to continue: "
read confirm
if [ "$confirm" != "YES" ]; then
    rm -f /tmp/*_pass
    exit 0
fi

log "Starting installation..."

# Cleanup
for mount in $(mount | grep /mnt | awk '{print $3}' | sort -r); do
    umount "$mount" 2>/dev/null || true
done
[ -e /dev/mapper/main ] && cryptsetup luksClose main 2>/dev/null || true

# Time and mirrors
log "Setting timezone and updating mirrors..."
timedatectl set-timezone Australia/Melbourne
timedatectl set-ntp true

if command -v reflector &> /dev/null; then
    reflector -c Australia -c "New Zealand" -f 10 --sort rate --save /etc/pacman.d/mirrorlist
fi

# Partitioning
log "Partitioning $TARGET_DISK..."
sgdisk --zap-all $TARGET_DISK
sgdisk --clear $TARGET_DISK
sgdisk --new=1:0:+1G --typecode=1:ef00 $TARGET_DISK
sgdisk --new=2:0:0 --typecode=2:8300 $TARGET_DISK

# Force partition table reload
partprobe $TARGET_DISK
sleep 3

# Set partition names
if [[ $TARGET_DISK == *"nvme"* ]]; then
    EFI_PARTITION="${TARGET_DISK}p1"
    ROOT_PARTITION="${TARGET_DISK}p2"
else
    EFI_PARTITION="${TARGET_DISK}1"
    ROOT_PARTITION="${TARGET_DISK}2"
fi

# Wait for partitions
log "Waiting for partitions..."
for i in {1..15}; do
    if [ -b "$ROOT_PARTITION" ] && [ -b "$EFI_PARTITION" ]; then
        break
    fi
    sleep 1
    partprobe $TARGET_DISK
done

if [ ! -b "$ROOT_PARTITION" ]; then
    error "Partition $ROOT_PARTITION not available"
    lsblk
    exit 1
fi

log "Partitions ready: $EFI_PARTITION, $ROOT_PARTITION"

# Clean partition thoroughly
log "Cleaning partition..."
wipefs -af $ROOT_PARTITION
dd if=/dev/zero of=$ROOT_PARTITION bs=1M count=10 2>/dev/null

# Encryption with file-based password
log "Setting up LUKS encryption..."
if ! cryptsetup luksFormat --type luks2 --pbkdf argon2id $ROOT_PARTITION < "$ENCRYPTION_PASSWORD_FILE"; then
    error "Failed to create LUKS encryption"
    rm -f /tmp/*_pass
    exit 1
fi

log "Opening encrypted partition..."
if ! cryptsetup luksOpen $ROOT_PARTITION main < "$ENCRYPTION_PASSWORD_FILE"; then
    error "Failed to open encrypted partition"
    rm -f /tmp/*_pass
    exit 1
fi

log "✓ Encryption setup complete"

# Filesystem
log "Creating BTRFS filesystem..."
mkfs.fat -F32 $EFI_PARTITION
mkfs.btrfs -f /dev/mapper/main

# BTRFS subvolumes
log "Creating BTRFS subvolumes..."
mount /dev/mapper/main /mnt
btrfs subvolume create /mnt/@
btrfs subvolume create /mnt/@home
umount /mnt

# Mount with optimization
mount -o noatime,ssd,compress=zstd,space_cache=v2,discard=async,subvol=@ /dev/mapper/main /mnt
mkdir -p /mnt/home /mnt/boot
mount -o noatime,ssd,compress=zstd,space_cache=v2,discard=async,subvol=@home /dev/mapper/main /mnt/home
mount $EFI_PARTITION /mnt/boot

# Install base system
log "Installing base system..."
pacstrap /mnt base linux linux-headers linux-firmware

# Generate fstab
genfstab -U -p /mnt >> /mnt/etc/fstab

# Copy password files to chroot
cp "$USER_PASSWORD_FILE" /mnt/tmp/user_pass
cp "$ENCRYPTION_PASSWORD_FILE" /mnt/tmp/encrypt_pass

# Configure in chroot
log "Configuring system..."
arch-chroot /mnt /bin/bash << CHROOT_END
set -e

# Timezone
ln -sf /usr/share/zoneinfo/Australia/Melbourne /etc/localtime
hwclock --systohc

# Packages
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
cat > /etc/hosts << EOF
127.0.0.1 localhost
::1 localhost
127.0.1.1 $HOSTNAME.localdomain $HOSTNAME
EOF

# User setup
useradd -m -G wheel $USERNAME
echo "$USERNAME ALL=(ALL) ALL" > /etc/sudoers.d/$USERNAME

# Set passwords from files
USER_PASS=\$(cat /tmp/user_pass 2>/dev/null || echo "defaultpass")
echo "root:\$USER_PASS" | chpasswd
echo "$USERNAME:\$USER_PASS" | chpasswd

# Initramfs
sed -i 's/^MODULES=()/MODULES=(btrfs)/' /etc/mkinitcpio.conf
sed -i 's/^HOOKS=(.*)/HOOKS=(base udev autodetect microcode modconf kms keyboard keymap consolefont block encrypt filesystems fsck)/' /etc/mkinitcpio.conf
mkinitcpio -p linux

# GRUB installation
grub-install --target=x86_64-efi --efi-directory=/boot --bootloader-id=grub

# Get UUID and configure GRUB properly
ROOT_UUID=\$(blkid -s UUID -o value $ROOT_PARTITION)
echo "Configuring GRUB with UUID: \$ROOT_UUID"

# Update GRUB default file
sed -i "s|^GRUB_CMDLINE_LINUX_DEFAULT=.*|GRUB_CMDLINE_LINUX_DEFAULT=\"loglevel=3 quiet cryptdevice=UUID=\$ROOT_UUID:main root=/dev/mapper/main\"|" /etc/default/grub
sed -i 's/^#GRUB_ENABLE_CRYPTODISK=y/GRUB_ENABLE_CRYPTODISK=y/' /etc/default/grub

# Verify GRUB config
echo "GRUB configuration check:"
grep "GRUB_CMDLINE_LINUX_DEFAULT" /etc/default/grub
grep "GRUB_ENABLE_CRYPTODISK" /etc/default/grub

# Generate GRUB config
grub-mkconfig -o /boot/grub/grub.cfg

# Enable services
systemctl enable NetworkManager sshd firewalld reflector.timer fstrim.timer

# Cleanup
rm -f /tmp/user_pass /tmp/encrypt_pass

echo "System configuration complete!"
CHROOT_END

# Cleanup password files
rm -f /tmp/*_pass

log "✓ Installation completed successfully!"

echo ""
info "Installation Summary:"
echo "  Target: $TARGET_DISK"
echo "  Hostname: $HOSTNAME"
echo "  Username: $USERNAME"
echo "  Encryption: LUKS2 with BTRFS"
echo ""
info "Next steps after reboot:"
echo "  1. Connect to WiFi: nmcli dev wifi connect SSID --ask" 
echo "  2. Update system: sudo pacman -Syu"
echo ""

echo -n "Reboot now? [Y/n]: "
read reboot_now
if [[ ! "$reboot_now" =~ ^[Nn]$ ]]; then
    log "Rebooting..."
    sleep 2
    reboot
fi
