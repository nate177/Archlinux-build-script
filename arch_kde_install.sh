#!/bin/bash

# Exit on any error
set -e

# Define variables (replace/dev/sdb" with your actual drive! run lsblk to list your drive!
DISK="/dev/sdb"
HOSTNAME="archlinux"
USERNAME="nathan"
PASSWORD="Placeholder change!"
TIMEZONE="Canada/Atlantic"
KEYMAP="us"

# Update system clock
timedatectl set-ntp true

# Partition the disk
# - EFI partition: 512M
# - Root partition: remaining space
parted -s "$DISK" mklabel gpt
parted -s "$DISK" mkpart primary fat32 1MiB 513MiB
parted -s "$DISK" set 1 esp on
parted -s "$DISK" mkpart primary ext4 513MiB 100%
mkfs.fat -F32 "${DISK}1"
mkfs.ext4 "${DISK}2"

# Mount the partitions
mount "${DISK}2" /mnt
mkdir /mnt/boot
mount "${DISK}1" /mnt/boot

# Install base system
pacstrap /mnt base linux linux-firmware linux-lts linux-lts-headers intel-ucode

# Generate fstab
genfstab -U /mnt >> /mnt/etc/fstab

# Chroot into the new system
arch-chroot /mnt /bin/bash <<EOF

# Set timezone
ln -sf /usr/share/zoneinfo/$TIMEZONE /etc/localtime
hwclock --systohc

# Set locale
echo "en_US.UTF-8 UTF-8" > /etc/locale.gen
locale-gen
echo "LANG=en_US.UTF-8" > /etc/locale.conf
echo "KEYMAP=$KEYMAP" > /etc/vconsole.conf

# Set hostname
echo "$HOSTNAME" > /etc/hostname
cat <<HOSTS > /etc/hosts
127.0.0.1   localhost
::1         localhost
127.0.1.1   $HOSTNAME.localdomain $HOSTNAME
HOSTS

# Set root password
echo "root:$PASSWORD" | chpasswd

# Install and configure bootloader (GRUB)
pacman -S --noconfirm grub efibootmgr
grub-install --target=x86_64-efi --efi-directory=/boot --bootloader-id=GRUB
grub-mkconfig -o /boot/grub/grub.cfg

# Install network utilities
pacman -S --noconfirm networkmanager
systemctl enable NetworkManager

# Install KDE Plasma and essential packages
pacman -S --noconfirm plasma kde-applications xorg sddm

# Install other essential packages
pacman -S --noconfirm firefox firefox-ublock-origin

# Install cups and gutenprint!
pacman -S --noconfirm cups gutenprint

# Enable sddm and cups
systemctl enable sddm
systemctl enable cups

# Create a user
useradd -m -G wheel -s /bin/bash $USERNAME
echo "$USERNAME:$PASSWORD" | chpasswd

# Enable sudo for wheel group
echo "%wheel ALL=(ALL) ALL" >> /etc/sudoers.d/wheel

# Exit chroot
exit
EOF

# Unmount and reboot
umount -R /mnt
reboot
