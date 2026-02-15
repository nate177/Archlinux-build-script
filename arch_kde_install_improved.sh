#!/bin/bash

# Improved Arch KDE Installation Script
# Date: 2026-02-15 07:19:28 UTC
# Author: nate177

set -e  # Exit immediately if a command exits with a non-zero status

echo "Starting Arch KDE installation..."

# Function to check if a package is installed
check_package_installed() {
    if ! pacman -Q $1 &>/dev/null; then
        return 1 # package not installed
    fi
    return 0 # package is installed
}

# Get user input for hostname
read -p "Enter the hostname for your system: " hostname
if [[ -z "$hostname" ]]; then
    echo "Hostname cannot be empty!"
    exit 1
fi

# Update system and install necessary packages
echo "Updating the system..."
pacman -Syu --noconfirm

# Check and install necessary packages
required_packages=("xorg" "plasma" "sddm" "kde-applications")
for package in "${required_packages[@]}"; do
    if ! check_package_installed "$package"; then
        echo "Installing $package..."
        pacman -S --noconfirm "$package"
    else
        echo "$package is already installed."
    fi
done

# Enable display manager
systemctl enable sddm

# Set hostname
hostnamectl set-hostname "$hostname"
echo "Hostname set to $hostname"

# Final status
echo "Arch KDE installation completed successfully!"