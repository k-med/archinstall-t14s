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
WIFI_INTERFACE=""

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

# Function to validate hostname
validate_hostname() {
    local hostname=$1
    if [[ ! "$hostname" =~ ^[a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?$ ]]; then
        return 1
    fi
    if [[ ${#hostname} -gt 63 ]]; then
        return 1
    fi
    return 0
}

# Function to validate username
validate_username() {
    local username=$1
    if [[ ! "$username" =~ ^[a-z][a-z0-9_-]{0,31}$ ]]; then
        return 1
    fi
    # Check for reserved usernames
    local reserved=("root" "bin" "daemon" "adm" "lp" "sync" "shutdown" "halt" "mail" "operator" "games" "ftp" "nobody" "systemd-network" "dbus" "polkitd" "avahi" "cups" "rtkit" "uuidd" "systemd-oom")
    for reserved_name in "${reserved[@]}"; do
        if [[ "$username" == "$reserved_name" ]]; then
            return 1
        fi
    done
    return 0
}

# Function to validate password strength
validate_password() {
    local password=$1
    local min_length=8
    
    if [[ ${#password} -lt $min_length ]]; then
        print_error "Password must be at least $min_length characters long"
        return 1
    fi
    
    # Check for at least one letter and one number
    if [[ ! "$password" =~ [a-zA-Z] ]] || [[ ! "$password" =~ [0-9] ]]; then
        print_warning "Password should contain both letters and numbers for better security"
        read -p "Continue with this password anyway? (y/n): " confirm
        if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
            return 1
        fi
    fi
    
    return 0
}

# Function to get password with confirmation
get_password() {
    local prompt=$1
    local password=""
    local confirm=""
    
    while true; do
        read -s -p "$prompt: " password
        echo
        
        if [[ -z "$password" ]]; then
            print_error "Password cannot be empty"
            continue
        fi
        
        if ! validate_password "$password"; then
            continue
        fi
        
        read -s -p "Confirm $prompt: " confirm
        echo
        
        if [[ "$password" == "$confirm" ]]; then
            echo "$password"
            return 0
        else
            print_error "Passwords do not match. Please try again."
        fi
    done
}

# Function to get user inputs
get_user_inputs() {
    print_header "SYSTEM CONFIGURATION"
    
    # Hostname
    while true; do
        read -p "Enter hostname (e.g., mercury): " HOSTNAME
        if [[ -z "$HOSTNAME" ]]; then
            print_error "Hostname cannot be empty"
            continue
        fi
        if validate_hostname "$HOSTNAME"; then
            break
        else
            print_error "Invalid hostname. Use only letters, numbers, and hyphens. Max 63 characters."
        fi
    done
    
    # Username
    while true; do
        read -p "Enter username (lowercase, no spaces): " USERNAME
        if [[ -z "$USERNAME" ]]; then
            print_error "Username cannot be empty"
            continue
        fi
        if validate_username "$USERNAME"; then
            break
        else
            print_error "Invalid username. Must start with a letter, contain only lowercase letters, numbers, underscores, or hyphens. Max 32 characters."
        fi
    done
    
    # Passwords with confirmation
    print_status "Setting up passwords..."
    ROOT_PASSWORD=$(get_password "Enter root password")
    USER_PASSWORD=$(get_password "Enter user password for $USERNAME")
    ENCRYPTION_PASSWORD=$(get_password "Enter disk encryption password")
    
    # Summary
    echo
    print_status "Configuration Summary:"
    echo "  Hostname: $HOSTNAME"
    echo "  Username: $USERNAME"
    echo "  Passwords: Set and confirmed"
    echo
    read -p "Is this configuration correct? (y/n): " confirm
    if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
        print_status "Restarting configuration..."
        HOSTNAME=""
        USERNAME=""
        ROOT_PASSWORD=""
        USER_PASSWORD=""
        ENCRYPTION_PASSWORD=""
        get_user_inputs
        return
    fi
    
    print_status "Configuration saved!"
}

# Function to get WiFi interface
get_wifi_interface() {
    local interface
    interface=$(ip link show | awk '/state UP/ {gsub(/:/, "", $2); if($2 ~ /^wl/) print $2; exit}')
    if [[ -z "$interface" ]]; then
        interface=$(ip link show | awk '/^[0-9]+:/ {gsub(/:/, "", $2); if($2 ~ /^wl/) print $2; exit}')
    fi
    if [[ -z "$interface" ]]; then
        interface="wlan0"  # fallback
    fi
    echo "$interface"
}

# Function to connect to WiFi
setup_wifi() {
    print_header "WIFI SETUP"
    
    # Get WiFi interface
    WIFI_INTERFACE=$(get_wifi_interface)
    print_status "Using WiFi interface: $WIFI_INTERFACE"
    
    # Check if already connected
    if ping -c 1 google.com &> /dev/null; then
        print_status "Already connected to internet. Skipping WiFi setup."
        return 0
    fi
    
    local max_attempts=3
    local attempt=1
    
    while [[ $attempt -le $max_attempts ]]; do
        print_status "Scanning for networks (attempt $attempt/$max_attempts)..."
        iwctl station "$WIFI_INTERFACE" scan
        sleep 3
        
        print_status "Available WiFi networks:"
        iwctl station "$WIFI_INTERFACE" get-networks
        
        read -p "Enter WiFi SSID: " WIFI_SSID
        if [[ -z "$WIFI_SSID" ]]; then
            print_error "SSID cannot be empty"
            ((attempt++))
            continue
        fi
        
        read -s -p "Enter WiFi Password (leave empty for open network): " WIFI_PASSWORD
        echo
        
        print_status "Connecting to WiFi network: $WIFI_SSID"
        
        if [[ -z "$WIFI_PASSWORD" ]]; then
            iwctl station "$WIFI_INTERFACE" connect "$WIFI_SSID"
        else
            iwctl --passphrase="$WIFI_PASSWORD" station "$WIFI_INTERFACE" connect "$WIFI_SSID"
        fi
        
        sleep 5
        
        print_status "Testing internet connection..."
        if ping -c 3 8.8.8.8 &> /dev/null; then
            print_status "Internet connection successful!"
            return 0
        else
            print_error "Failed to connect to internet."
            if [[ $attempt -lt $max_attempts ]]; then
                read -p "Try again? (y/n): " retry
                if [[ ! "$retry" =~ ^[Yy]$ ]]; then
                    break
                fi
            fi
            ((attempt++))
        fi
    done
    
    print_error "Could not establish internet connection after $max_attempts attempts."
    read -p "Continue without internet? (Not recommended, y/n): " continue_offline
    if [[ ! "$continue_offline" =~ ^[Yy]$ ]]; then
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
    
    while true; do
        print_status "Available disks:"
        lsblk -d -o NAME,SIZE,MODEL | grep -E "(nvme|sd[a-z]|vd[a-z])" || {
            print_error "No suitable disks found!"
            exit 1
        }
        
        read -p "Enter target disk name (e.g., nvme0n1, sda): " TARGET_DISK
        
        if [[ -z "$TARGET_DISK" ]]; then
            print_error "Disk name cannot be empty"
            continue
        fi
        
        # Add /dev/ prefix if not present
        if [[ ! "$TARGET_DISK" =~ ^/dev/ ]]; then
            TARGET_DISK="/dev/$TARGET_DISK"
        fi
        
        # Validate disk exists
        if [[ ! -b "$TARGET_DISK" ]]; then
            print_error "Disk $TARGET_DISK does not exist!"
            continue
        fi
        
        # Show current partition table
        print_status "Current partition table for $TARGET_DISK:"
        lsblk "$TARGET_DISK" 2>/dev/null || {
            print_warning "Could not read partition table"
        }
        
        # Confirm disk selection
        echo
        print_warning "WARNING: This will COMPLETELY ERASE $TARGET_DISK!"
        print_warning "All existing data will be permanently lost!"
        echo
        read -p "Type 'DESTROY' to confirm (case sensitive): " confirm
        
        if [[ "$confirm" == "DESTROY" ]]; then
            break
        else
            print_error "Confirmation failed. Please try again."
        fi
    done
    
    print_status "Partitioning $TARGET_DISK..."
    
    # Unmount any existing partitions
    umount "${TARGET_DISK}"* 2>/dev/null || true
    
    # Close any existing LUKS devices
    cryptsetup close main 2>/dev/null || true
    
    # Wipe filesystem signatures
    wipefs -af "$TARGET_DISK"
    
    # Create GPT partition table and partitions
    if ! sgdisk -Z "$TARGET_DISK"; then
        print_error "Failed to create new partition table"
        exit 1
    fi
    
    if ! sgdisk -n 1:0:+1G -t 1:ef00 -c 1:"EFI System" "$TARGET_DISK"; then
        print_error "Failed to create EFI partition"
        exit 1
    fi
    
    if ! sgdisk -n 2:0:0 -t 2:8300 -c 2:"Linux filesystem" "$TARGET_DISK"; then
        print_error "Failed to create main partition"
        exit 1
    fi
    
    # Wait for kernel to recognize partitions
    sleep 2
    partprobe "$TARGET_DISK"
    sleep 2
    
    # Verify partitions were created
    if [[ ! -b "${TARGET_DISK}p1" && ! -b "${TARGET_DISK}1" ]]; then
        print_error "Partitions were not created successfully"
        exit 1
    fi
    
    print_status "Partitioning complete!"
    lsblk "$TARGET_DISK"
}

# Function to setup encryption and filesystems
setup_encryption_and_filesystems() {
    print_header "ENCRYPTION AND FILESYSTEM SETUP"
    
    # Determine partition naming scheme
    if [[ -b "${TARGET_DISK}p2" ]]; then
        EFI_PARTITION="${TARGET_DISK}p1"
        MAIN_PARTITION="${TARGET_DISK}p2"
    elif [[ -b "${TARGET_DISK}1" ]]; then
        EFI_PARTITION="${TARGET_DISK}1"
        MAIN_PARTITION="${TARGET_DISK}2"
    else
        print_error "Could not find created partitions!"
        exit 1
    fi
    
    print_status "Setting up LUKS encryption on $MAIN_PARTITION..."
    
    # Setup LUKS encryption with retry mechanism
    local max_attempts=3
    local attempt=1
    
    while [[ $attempt -le $max_attempts ]]; do
        if echo -n "$ENCRYPTION_PASSWORD" | cryptsetup luksFormat "$MAIN_PARTITION" --type luks2 --pbkdf pbkdf2 -; then
            print_status "LUKS encryption setup successful"
            break
        else
            print_error "Failed to setup LUKS encryption (attempt $attempt/$max_attempts)"
            if [[ $attempt -eq $max_attempts ]]; then
                exit 1
            fi
            ((attempt++))
            sleep 2
        fi
    done
    
    # Open encrypted partition
    if ! echo -n "$ENCRYPTION_PASSWORD" | cryptsetup luksOpen "$MAIN_PARTITION" main -; then
        print_error "Failed to open encrypted partition"
        exit 1
    fi
    
    # Verify encrypted device exists
    if [[ ! -b /dev/mapper/main ]]; then
        print_error "Encrypted device /dev/mapper/main was not created"
        exit 1
    fi
    
    print_status "Creating Btrfs filesystem..."
    if ! mkfs.btrfs -f /dev/mapper/main; then
        print_error "Failed to create Btrfs filesystem"
        exit 1
    fi
    
    print_status "Creating and mounting Btrfs subvolumes..."
    
    # Mount temporarily to create subvolumes
    if ! mount /dev/mapper/main /mnt; then
        print_error "Failed to mount encrypted partition"
        exit 1
    fi
    
    cd /mnt
    if ! btrfs subvolume create @; then
        print_error "Failed to create @ subvolume"
        cd /
        umount /mnt
        exit 1
    fi
    
    if ! btrfs subvolume create @home; then
        print_error "Failed to create @home subvolume"
        cd /
        umount /mnt
        exit 1
    fi
    
    cd /
    umount /mnt
    
    # Mount with optimized options
    print_status "Mounting root subvolume with optimized options..."
    if ! mount -o noatime,ssd,compress=zstd,space_cache=v2,discard=async,subvol=@ /dev/mapper/main /mnt; then
        print_error "Failed to mount root subvolume"
        exit 1
    fi
    
    if ! mkdir -p /mnt/home; then
        print_error "Failed to create /mnt/home directory"
        exit 1
    fi
    
    print_status "Mounting home subvolume..."
    if ! mount -o noatime,ssd,compress=zstd,space_cache=v2,discard=async,subvol=@home /dev/mapper/main /mnt/home; then
        print_error "Failed to mount home subvolume"
        exit 1
    fi
    
    print_status "Setting up EFI partition..."
    if ! mkfs.fat -F32 "$EFI_PARTITION"; then
        print_error "Failed to format EFI partition"
        exit 1
    fi
    
    if ! mkdir -p /mnt/boot; then
        print_error "Failed to create /mnt/boot directory"
        exit 1
    fi
    
    if ! mount "$EFI_PARTITION" /mnt/boot; then
        print_error "Failed to mount EFI partition"
        exit 1
    fi
    
    print_status "Filesystem setup complete!"
    print_status "Mount points:"
    df -h /mnt /mnt/home /mnt/boot
}

# Function to update mirrorlist
update_mirrors() {
    print_header "UPDATING MIRRORS"
    
    print_status "Updating pacman mirrorlist for Australia..."
    
    # Backup original mirrorlist
    cp /etc/pacman.d/mirrorlist /etc/pacman.d/mirrorlist.backup
    
    # Try reflector first
    if command -v reflector >/dev/null 2>&1; then
        if reflector -c Australia -a 12 --sort rate --save /etc/pacman.d/mirrorlist; then
            print_status "Mirrors updated successfully with reflector"
            return 0
        else
            print_warning "Reflector failed, trying manual method..."
        fi
    fi
    
    # Fallback method if reflector fails
    if curl -s "https://archlinux.org/mirrorlist/?country=AU&protocol=https&use_mirror_status=on" | \
       sed -e 's/^#Server/Server/' -e '/^#/d' > /etc/pacman.d/mirrorlist; then
        print_status "Mirrors updated successfully with manual method"
    else
        print_warning "Mirror update failed, using backup"
        mv /etc/pacman.d/mirrorlist.backup /etc/pacman.d/mirrorlist
    fi
    
    # Verify mirrorlist has content
    if [[ ! -s /etc/pacman.d/mirrorlist ]]; then
        print_error "Mirrorlist is empty! Using fallback mirrors."
        cat > /etc/pacman.d/mirrorlist << 'EOF'
Server = https://mirror.aarnet.edu.au/pub/archlinux/$repo/os/$arch
Server = https://archlinux.mirror.digitalpacific.com.au/$repo/os/$arch
Server = https://ftp.swin.edu.au/archlinux/$repo/os/$arch
EOF
    fi
    
    print_status "Mirrors configured!"
}

# Function to install base system
install_base_system() {
    print_header "INSTALLING BASE SYSTEM"
    
    print_status "Installing base packages..."
    local max_attempts=3
    local attempt=1
    
    while [[ $attempt -le $max_attempts ]]; do
        if pacstrap /mnt base linux linux-headers linux-firmware; then
            print_status "Base packages installed successfully"
            break
        else
            print_error "Failed to install base packages (attempt $attempt/$max_attempts)"
            if [[ $attempt -eq $max_attempts ]]; then
                print_error "Could not install base system after $max_attempts attempts"
                exit 1
            fi
            print_status "Refreshing package databases and trying again..."
            pacman -Sy
            ((attempt++))
        fi
    done
    
    print_status "Generating fstab..."
    if ! genfstab -U -p /mnt >> /mnt/etc/fstab; then
        print_error "Failed to generate fstab"
        exit 1
    fi
    
    # Verify fstab was created properly
    if [[ ! -s /mnt/etc/fstab ]]; then
        print_error "fstab is empty!"
        exit 1
    fi
    
    print_status "Generated fstab:"
    cat /mnt/etc/fstab
    
    print_status "Base system installed!"
}

# Function to configure system in chroot
configure_system() {
    print_header "CONFIGURING SYSTEM"
    
    print_status "Entering chroot and configuring system..."
    
    # Get the correct partition name for UUID lookup
    local main_partition
    if [[ -b "${TARGET_DISK}p2" ]]; then
        main_partition="${TARGET_DISK}p2"
    elif [[ -b "${TARGET_DISK}2" ]]; then
        main_partition="${TARGET_DISK}2"
    else
        print_error "Could not determine main partition name"
        exit 1
    fi
    
    # Create configuration script to run in chroot
    cat > /mnt/configure_system.sh << 'CHROOT_EOF'
#!/bin/bash
set -e

print_status() {
    echo -e "\033[0;32m[INFO]\033[0m $1"
}

print_error() {
    echo -e "\033[0;31m[ERROR]\033[0m $1"
}

# Set timezone
print_status "Setting timezone..."
ln -sf /usr/share/zoneinfo/Australia/Melbourne /etc/localtime
hwclock --systohc

# Install essential packages with retry
print_status "Installing essential packages..."
max_attempts=3
attempt=1

packages="vim sudo base-devel btrfs-progs grub efibootmgr mtools networkmanager network-manager-applet openssh git iptables-nft ipset firewalld acpid reflector grub-btrfs amd-ucode mesa xf86-video-amdgpu man-db man-pages"

while [[ $attempt -le $max_attempts ]]; do
    if pacman -S --noconfirm $packages; then
        print_status "Packages installed successfully"
        break
    else
        print_error "Package installation failed (attempt $attempt/$max_attempts)"
        if [[ $attempt -eq $max_attempts ]]; then
            print_error "Could not install packages after $max_attempts attempts"
            exit 1
        fi
        pacman -Sy
        ((attempt++))
    fi
done

# Configure locale
print_status "Configuring locale..."
echo "en_AU.UTF-8 UTF-8" >> /etc/locale.gen
locale-gen
echo "LANG=en_AU.UTF-8" > /etc/locale.conf
echo "KEYMAP=us" > /etc/vconsole.conf

# Configure mkinitcpio for encryption
print_status "Configuring mkinitcpio..."
sed -i 's/^MODULES=.*/MODULES=(btrfs)/' /etc/mkinitcpio.conf
sed -i 's/^HOOKS=.*/HOOKS=(base udev autodetect microcode modconf kms keyboard keymap consolefont block encrypt filesystems fsck)/' /etc/mkinitcpio.conf

if ! mkinitcpio -p linux; then
    print_error "Failed to generate initramfs"
    exit 1
fi

# Install and configure GRUB
print_status "Installing GRUB bootloader..."
if ! grub-install --target=x86_64-efi --efi-directory=/boot --bootloader-id=grub; then
    print_error "GRUB installation failed"
    exit 1
fi

print_status "System configuration complete in chroot!"
CHROOT_EOF
    
    # Make script executable and run in chroot
    chmod +x /mnt/configure_system.sh
    
    if ! arch-chroot /mnt /configure_system.sh; then
        print_error "System configuration failed in chroot"
        exit 1
    fi
    
    # Now configure the remaining items that need variables from the host
    print_status "Configuring system settings..."
    
    # Set hostname
    echo "$HOSTNAME" > /mnt/etc/hostname
    
    # Configure hosts file
    cat > /mnt/etc/hosts << EOF
127.0.0.1   localhost
::1         localhost
127.0.1.1   $HOSTNAME.localdomain $HOSTNAME
EOF
    
    # Set passwords
    arch-chroot /mnt bash -c "echo 'root:$ROOT_PASSWORD' | chpasswd"
    arch-chroot /mnt useradd -m -g users -G wheel "$USERNAME"
    arch-chroot /mnt bash -c "echo '$USERNAME:$USER_PASSWORD' | chpasswd"
    
    # Configure sudo
    echo "$USERNAME ALL=(ALL) ALL" > /mnt/etc/sudoers.d/$USERNAME
    
    # Get UUID for encryption and configure GRUB
    local uuid
    uuid=$(blkid -s UUID -o value "$main_partition")
    if [[ -z "$uuid" ]]; then
        print_error "Could not get UUID for encrypted partition"
        exit 1
    fi
    
    # Configure GRUB for encryption
    sed -i "s/^GRUB_CMDLINE_LINUX_DEFAULT=.*/GRUB_CMDLINE_LINUX_DEFAULT=\"loglevel=3 quiet cryptdevice=UUID=$uuid:main root=\/dev\/mapper\/main\"/" /mnt/etc/default/grub
    
    # Generate GRUB config
    if ! arch-chroot /mnt grub-mkconfig -o /boot/grub/grub.cfg; then
        print_error "Failed to generate GRUB configuration"
        exit 1
    fi
    
    # Enable services
    print_status "Enabling system services..."
    arch-chroot /mnt systemctl enable NetworkManager
    arch-chroot /mnt systemctl enable sshd
    arch-chroot /mnt systemctl enable firewalld
    arch-chroot /mnt systemctl enable reflector.timer
    arch-chroot /mnt systemctl enable fstrim.timer
    arch-chroot /mnt systemctl enable acpid
    
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
    echo "  Disk: $TARGET_DISK"
    echo "  Filesystem: Btrfs with LUKS encryption"
    echo "  WiFi Interface: ${WIFI_INTERFACE:-Auto-detected}"
    echo
    echo -e "${YELLOW}Post-Installation Notes:${NC}"
    echo "  • After reboot, you'll need to enter your disk encryption password"
    echo "  • Connect to WiFi with: nmcli device wifi connect \"SSID\" --ask"
    echo "  • Update system with: sudo pacman -Syu"
    echo "  • Install additional software as needed"
    echo
    
    # Verify critical files exist before rebooting
    local critical_files=(
        "/mnt/boot/grub/grub.cfg"
        "/mnt/etc/fstab"
        "/mnt/etc/hostname"
        "/mnt/etc/passwd"
    )
    
    print_status "Performing final verification..."
    for file in "${critical_files[@]}"; do
        if [[ ! -f "$file" ]]; then
            print_error "Critical file missing: $file"
            print_error "Installation may not boot properly!"
            read -p "Continue anyway? (y/n): " continue_anyway
            if [[ ! "$continue_anyway" =~ ^[Yy]$ ]]; then
                exit 1
            fi
            break
        fi
    done
    
    print_status "System verification completed successfully!"
    echo
    print_warning "The system will now reboot into your new Arch Linux installation."
    
    local reboot_choice
    while true; do
        read -p "Reboot now? (y/n): " reboot_choice
        case "$reboot_choice" in
            [Yy]|[Yy][Ee][Ss])
                print_status "Unmounting filesystems and rebooting..."
                sync
                umount -R /mnt 2>/dev/null || {
                    print_warning "Some filesystems could not be unmounted cleanly"
                }
                cryptsetup close main 2>/dev/null || true
                reboot
                break
                ;;
            [Nn]|[Nn][Oo])
                print_status "Installation complete. You can manually reboot with:"
                print_status "  sync && umount -R /mnt && cryptsetup close main && reboot"
                break
                ;;
            *)
                print_error "Please answer yes (y) or no (n)"
                ;;
        esac
    done
}

# Main installation function
main() {
    print_header "ARCH LINUX AUTOMATED INSTALLER"
    echo -e "${YELLOW}This script will install Arch Linux with:${NC}"
    echo "  • LUKS full-disk encryption"
    echo "  • Btrfs filesystem with compression"
    echo "  • GRUB bootloader with UEFI support"
    echo "  • AMD-optimized drivers and microcode"
    echo "  • Essential system services"
    echo
    print_warning "IMPORTANT: This will completely erase the selected disk!"
    print_warning "Make sure you have backed up any important data."
    echo
    
    read -p "Do you want to continue? (y/n): " continue_install
    if [[ ! "$continue_install" =~ ^[Yy]$ ]]; then
        print_status "Installation cancelled by user."
        exit 0
    fi
    
    # Run installation steps
    local steps=(
        "get_user_inputs"
        "setup_wifi" 
        "setup_system_basics"
        "partition_disk"
        "setup_encryption_and_filesystems"
        "update_mirrors"
        "install_base_system"
        "configure_system"
        "complete_installation"
    )
    
    for step in "${steps[@]}"; do
        if ! $step; then
            print_error "Installation step '$step' failed!"
            exit 1
        fi
    done
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
