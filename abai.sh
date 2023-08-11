#!/bin/bash

# Set parameters
echo "WARNING: Choose the correct disk, this script will erase all data on the disk."
echo "Enter the disk device (e.g. /dev/sda):"
read disk
if [[ ! -b "$disk" ]]; then
  echo "Error: Invalid disk device $disk"
exit 1
fi

# Set hostname
while [[ -z $hostname ]]
do
    read -p "Enter the hostname: " hostname
done

# Set username
while [[ -z $username ]]
do
    read -p "Enter the username: " username
done

# Set password
while [[ -z $password ]]
do
    read -s -p "Enter the password: " password
    echo
done

# Set root password
while [[ -z $rootpassword ]]
do
    read -s -p "Enter the root password: " rootpassword
    echo
done

# Check if root password is strong enough
while true
do
    if [[ ${#rootpassword} -lt 8 ]]; then
        echo "Password is too short. Enter at least 8 characters."
        read -s -p "Enter the root password again: " rootpassword
    elif [[ $rootpassword =~ [A-Z] && $rootpassword =~ [a-z] && $rootpassword =~ [0-9] ]]; then
        break
    else
        echo "Password is not strong enough. It should contain at least one uppercase letter, one lowercase letter, and one number."
        read -s -p "Enter the root password again: " rootpassword
    fi
    echo
done

# Set timezone
echo "Enter the timezone (e.g. America/Los_Angeles):"
read timezone

# Set locale
echo "Enter the locale (e.g. en_US.UTF-8):"
read locale

# Zap the disk
sgdisk --zap-all ${disk}

# Partition the disk
sgdisk -Z ${disk}
sgdisk -n 1:0:+1024M -t 1:ef00 ${disk}
sgdisk -n 2:0:+16G -t 2:8200 ${disk}
sgdisk -n 3:0:+40G -t 3:8300 ${disk}
sgdisk -n 4:0:0 -t 4:8300 ${disk}

# Label partitions
sgdisk --change-name=1:boot /dev/sda1
sgdisk --change-name=2:swap /dev/sda2
sgdisk --change-name=3:root /dev/sda3
sgdisk --change-name=4:home /dev/sda4

# Format the partitions
mkfs.fat -F32 ${disk}1
mkswap ${disk}2
swapon ${disk}2
mkfs.ext4 ${disk}3
mkfs.ext4 ${disk}4

# Mount the file system
mount ${disk}3 /mnt
mkdir /mnt/boot
mkdir /mnt/home
mount ${disk}1 /mnt/boot

# Update mirror list
cp /etc/pacman.d/mirrorlist /etc/pacman.d/mirrorlist.backup
pacman -Sy pacman-contrib --noconfirm
rankmirrors -n 6 /etc/pacman.d/mirrorlist.backup > /etc/pacman.d/mirrorlist

# Install the base packages
pacstrap -K /mnt base linux linux-firmware base-devel networkmanager iproute2 iwd dhcpcd git nano sudo htop bash bash-completion

# Generate fstab
genfstab -U -p /mnt >> /mnt/etc/fstab

# Set locale
echo "${locale} UTF-8" > /mnt/etc/locale.gen
arch-chroot /mnt /bin/bash -c "locale-gen"
echo "LANG=${locale}" > /mnt/etc/locale.conf
arch-chroot /mnt /bin/bash -c "export LANG=${locale}"

# Set timezone
arch-chroot /mnt /bin/bash -c "ln -s /usr/share/zoneinfo/${timezone} /etc/localtime"
arch-chroot /mnt /bin/bash -c "hwclock --systohc --utc"

# Set hostname
echo "${hostname}" > /mnt/etc/hostname

# Enable trim support (SSD's only)
systemctl enable fstrim.timer

# Enable multilib repository
echo "[multilib]" >> /mnt/etc/pacman.conf
echo "Include = /etc/pacman.d/mirrorlist" >> /mnt/etc/pacman.conf
arch-chroot /mnt /bin/bash -c "pacman -Sy"

# Set the root password
arch-chroot /mnt /bin/bash -c "echo root:${rootpassword} | chpasswd"

# Create a user
arch-chroot /mnt /bin/bash -c "useradd -m -g users -G wheel,storage,power -s /bin/bash ${username}"
arch-chroot /mnt /bin/bash -c "echo '${username}:${password}' | chpasswd"
arch-chroot /mnt /bin/bash -c "sed -i 's/# %wheel ALL=(ALL) ALL/%wheel ALL=(ALL) ALL/g' /etc/sudoers"
sed -i "s/# %wheel ALL=(ALL) ALL/%wheel ALL=(ALL) ALL/g" /mnt/etc/sudoers
echo "Defaults rootpw" >> /mnt/etc/sudoers

# Install bootloader
arch-chroot /mnt /bin/bash -c "bootctl install"
touch /mnt/boot/loader/entries/arch.conf
echo "title Arch" > /mnt/boot/loader/entries/arch.conf
echo "linux /vmlinuz-linux" >> /mnt/boot/loader/entries/arch.conf
echo "initrd /initramfs-linux.img" >> /mnt/boot/loader/entries/arch.conf
echo "options root=PARTUUID=$(blkid -s PARTUUID -o value /dev/sda3) rw" >> /mnt/boot/loader/entries/arch.conf

#Enable DHCP
arch-chroot /mnt /bin/bash -c "systemctl enable dhcpcd.service"

#Enable NetworkManager
arch-chroot /mnt /bin/bash -c "systemctl enable NetworkManager.service"

# Unmount file system and reboot
umount -R /mnt
reboot