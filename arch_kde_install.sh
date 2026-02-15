#!/bin/bash

# Arch Linux KDE Install Script - Improved Version
# This script automates Arch Linux installation with KDE Plasma

set -euo pipefail

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Logging function
log() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1" >&2
}

warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

# Error handling and cleanup
trap 'error "Error occurred on line $LINENO"; cleanup' ERR
trap 'cleanup' EXIT INT

cleanup() {
    log "Performing cleanup..."
    if mountpoint -q /mnt/boot; then
        umount /mnt/boot 2>/dev/null || true
    fi
    if mountpoint -q /mnt; then
        umount -R /mnt 2>/dev/null || true
    fi
}

# Verify running as root
if [[ $EUID -ne 0 ]]; then
    error "This script must be run as root (use sudo)"
    exit 1
fi

# Function to prompt for input
prompt_input() {
    local prompt="$1"
    local default="$2"
    local input
    
    read -p "${prompt} [${default}]: " input
    echo "${input:-$default}"
}

prompt_password() {
    local prompt="$1"
    local password
    local password_confirm
    
    while true; do
        read -sp "${prompt}: " password
        echo
        read -sp "Confirm ${prompt}: " password_confirm
        echo
        
        if [[ "$password" == "$password_confirm" ]]; then
            echo "$password"
            break
        else
            error "Passwords do not match. Please try again."
        fi
    done
}

# Validate block device
validate_disk() {
    local disk="$1"
    if [[ ! -b "$disk" ]]; then
        error "$disk is not a valid block device"
        echo "Available devices:"
        lsblk -d
        exit 1
    fi
}

# Confirm disk selection
confirm_disk() {
    local disk="$1"
    echo -e "\n${YELLOW}WARNING: This will erase all data on $disk!${NC}"
    lsblk "$disk"
    read -p "Continue with $disk? (yes/no): " -r response
    if [[ ! "$response" =~ ^[Yy][Ee][Ss]$ ]]; then
        log "Installation cancelled"
        exit 0
    fi
}

# ============= Configuration Section =============
log "=== Arch Linux KDE Installation Script ==="
echo

# Get disk from user
while true; do
    DISK=$(prompt_input "Enter the disk to install to (e.g., /dev/sdb)" "/dev/sdb")
    validate_disk "$DISK"
    confirm_disk "$DISK"
    break
done

HOSTNAME=$(prompt_input "Enter hostname" "archlinux")
USERNAME=$(prompt_input "Enter username for new user" "nathan")
TIMEZONE=$(prompt_input "Enter timezone (e.g., Canada/Atlantic)" "Canada/Atlantic")
KEYMAP=$(prompt_input "Enter keymap (e.g., us)" "us")

log "Getting passwords..."
ROOT_PASSWORD=$(prompt_password "Root password")
USER_PASSWORD=$(prompt_password "User password for $USERNAME")

# Confirm configuration
log "=== Installation Configuration ==="
echo "Disk:       $DISK"
echo "Hostname:   $HOSTNAME"
echo "Username:   $USERNAME"
echo "Timezone:   $TIMEZONE"
echo "Keymap:     $KEYMAP"
echo

read -p "Proceed with installation? (yes/no): " -r response
if [[ ! "$response" =~ ^[Yy][Ee][Ss]$ ]]; then
    log "Installation cancelled"
    exit 0
fi

# ============= Installation Section =============
log "Updating system clock..."
timedatectl set-ntp true

log "Partitioning disk $DISK..."
# Create GPT partition table
parted -s "$DISK" mklabel gpt

# EFI partition: 512MB
parted -s "$DISK" mkpart primary fat32 1MiB 513MiB
parted -s "$DISK" set 1 esp on

# Swap partition: 4GB (adjust as needed)
parted -s "$DISK" mkpart primary linux-swap 513MiB 4613MiB

# Root partition: remaining space
parted -s "$DISK" mkpart primary ext4 4613MiB 100%

log "Formatting partitions..."
mkfs.fat -F32 "${DISK}1"
mkswap "${DISK}2"
mkfs.ext4 "${DISK}3"

log "Mounting partitions..."
mount "${DISK}3" /mnt
mkdir -p /mnt/boot
mount "${DISK}1" /mnt/boot

log "Enabling swap..."
swapon "${DISK}2"

log "Installing base system..."
pacstrap /mnt base linux linux-firmware linux-lts linux-lts-headers intel-ucode

log "Generating fstab..."
genfstab -U /mnt >> /mnt/etc/fstab

log "Configuring new system..."
# Chroot into the new system
arch-chroot /mnt /bin/bash <<EOF
set -euo pipefail

echo "[*] Setting timezone..."
ln -sf /usr/share/zoneinfo/${TIMEZONE} /etc/localtime
hwclock --systohc

echo "[*] Setting locale..."
echo "en_US.UTF-8 UTF-8" > /etc/locale.gen
locale-gen
echo "LANG=en_US.UTF-8" > /etc/locale.conf
echo "KEYMAP=${KEYMAP}" > /etc/vconsole.conf

echo "[*] Setting hostname..."
echo "${HOSTNAME}" > /etc/hostname
cat > /etc/hosts <<HOSTS
127.0.0.1   localhost
::1         localhost
127.0.1.1   ${HOSTNAME}.localdomain ${HOSTNAME}
HOSTS

echo "[*] Setting root password..."
echo "root:${ROOT_PASSWORD}" | chpasswd

echo "[*] Installing GRUB bootloader..."
pacman -S --noconfirm grub efibootmgr
grub-install --target=x86_64-efi --efi-directory=/boot --bootloader-id=GRUB
grub-mkconfig -o /boot/grub/grub.cfg

echo "[*] Installing NetworkManager..."
pacman -S --noconfirm networkmanager
systemctl enable NetworkManager

echo "[*] Installing KDE Plasma..."
pacman -S --noconfirm plasma kde-applications xorg sddm

echo "[*] Installing additional packages..."
pacman -S --noconfirm firefox firefox-ublock-origin

echo "[*] Installing printing support..."
pacman -S --noconfirm cups gutenprint ghostscript print-manager

echo "[*] Enabling services..."
systemctl enable sddm
systemctl enable cups

echo "[*] Creating user account..."
useradd -m -G wheel -s /bin/bash ${USERNAME}
echo "${USERNAME}:${USER_PASSWORD}" | chpasswd

echo "[*] Configuring sudo for wheel group..."
echo "%wheel ALL=(ALL) NOPASSWD:ALL" | tee /etc/sudoers.d/wheel
chmod 0440 /etc/sudoers.d/wheel

echo "[*] System configuration complete!"
EOF

log "Installation complete!"
log "The system will reboot in 10 seconds..."
log "Press Ctrl+C to cancel"
sleep 10

log "Rebooting system..."
reboot
