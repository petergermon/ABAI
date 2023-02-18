#!/bin/bash

# Set parameters
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

# Set timezone
echo "Enter the timezone (e.g. America/Los_Angeles):"
read timezone

# Set locale
echo "Enter the locale (e.g. en_US.UTF-8):"
read locale

# Set keymap
echo "Enter the keymap (e.g. us):"
read keymap

# Partition the disk
sgdisk -Z ${disk}
sgdisk -n 1:0:+512M -t 1:ef00 ${disk}
sgdisk -n 2:0:0 -t 2:8300 ${disk}

# Format the partitions
mkfs.fat -F32 ${disk}1
mkfs.ext4 ${disk}2

# Mount the file system
mount ${disk}2 /mnt
mkdir /mnt/boot
mount ${disk}1 /mnt/boot

# Install the base packages
pacstrap /mnt base base-devel iwd dhcpcd git efibootmgr

# Configure the system
genfstab -U /mnt >> /mnt/etc/fstab
echo "${hostname}" > /mnt/etc/hostname
arch-chroot /mnt /bin/bash -c "ln -sf /usr/share/zoneinfo/${timezone} /etc/localtime"
arch-chroot /mnt /bin/bash -c "hwclock --systohc"
echo "${locale} UTF-8" > /mnt/etc/locale.gen
arch-chroot /mnt /bin/bash -c "locale-gen"
echo "LANG=${locale}" > /mnt/etc/locale.conf
echo "KEYMAP=${keymap}" > /mnt/etc/vconsole.conf
echo "127.0.0.1 localhost" >> /mnt/etc/hosts
echo "::1 localhost" >> /mnt/etc/hosts
echo "127.0.1.1 ${hostname}.localdomain ${hostname}" >> /mnt/etc/hosts

# Set the root password
arch-chroot /mnt /bin/bash -c "echo root:${rootpassword} | chpasswd"

# Create a user
arch-chroot /mnt /bin/bash -c "useradd -m -g users -G wheel -s /bin/bash ${username}"
arch-chroot /mnt /bin/bash -c "echo '${username}:${password}' | chpasswd"
arch-chroot /mnt /bin/bash -c "pacman -S --noconfirm sudo"
arch-chroot /mnt /bin/bash -c "sed -i 's/# %wheel ALL=(ALL) ALL/%wheel ALL=(ALL) ALL/g' /etc/sudoers"

# Add user to sudoers
echo "${username} ALL=(ALL:ALL) ALL" >> /mnt/etc/sudoers

# Set PARTUUID for bootloader
#partuuid=$(blkid -s PARTUUID -o value /dev/sda2 | awk '{print $1}')

# Install and configure bootloader
arch-chroot /mnt /bin/bash -c "bootctl --path=/boot install"
echo "default arch" > /mnt/boot/loader/loader.conf
echo "timeout 4" >> /mnt/boot/loader/loader.conf
echo "console-mode  max" >> /mnt/boot/loader/loader.conf
echo "editor  0" >> /mnt/boot/loader/loader.conf
echo "title  Arch Linux" > /mnt/boot/loader/entries/arch.conf
echo "linux  /vmlinuz-linux" >> /mnt/boot/loader/entries/arch.conf
echo "initrd /initramfs-linux.img" >> /mnt/boot/loader/entries/arch.conf
echo "options  root=/dev/${disk}2 rw" >> /mnt/boot/loader/entries/arch.conf
#echo "options  root=PARTUUID=${partuuid} rw" >> /mnt/boot/loader/entries/arch.conf
#arch-chroot /mnt /bin/bash -c "efibootmgr --create --disk /dev/sda --part 2 --loader \"\EFI\systemd\systemd-bootx64.efi\" --label \"Linux Boot Manager\" --unicode"
#arch-chroot /mnt /bin/bash -c "bootctl --path=/boot update"

# Unmount file system and reboot
umount -R /mnt
reboot
