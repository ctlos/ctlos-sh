#!/bin/bash

chroot_path=$(cat /tmp/chroot_path.tmp)

[[ -d $chroot_path ]] || { echo "error: chroot path"; exit; }

if ! hash reflector >/dev/null 2>&1; then
  pacman -S reflector --noconfirm
  reflector -a 12 -l 30 -f 30 -p https --sort rate --save /etc/pacman.d/mirrorlist
else
  reflector -a 12 -l 30 -f 30 -p https --sort rate --save /etc/pacman.d/mirrorlist
fi

if ! hash pacstrap >/dev/null 2>&1; then
  pacman -S arch-install-scripts --noconfirm
fi

if [[ ! -f "/usr/bin/pacstrap.sh" ]]; then
sed -e '/chroot_add_mount proc/d' -e '/chroot_add_mount sys/d' -e '/ignore_error chroot_maybe_add_mount/d' -e '/chroot_add_mount udev/d' -e '/chroot_add_mount devpts/d' -e '/chroot_add_mount shm/d' -e '/chroot_add_mount \/run/d' -e '/chroot_add_mount tmp/d' -e '/efivarfs \"/d' /usr/bin/pacstrap >/usr/bin/pacstrap.sh
chmod +x /usr/bin/pacstrap.sh
fi

PKGS=(
base base-devel linux linux-firmware nano grub zsh
dhcpcd netctl iwd reflector
mkinitcpio-busybox mkinitcpio-nfs-utils inetutils jfsutils less mdadm perl s-nail sysfsutils systemd-sysvcompat usbutils device-mapper
cryptsetup e2fsprogs f2fs-tools btrfs-progs lvm2 reiserfsprogs xfsprogs
)

for i in "${PKGS[*]}"; do
  /usr/bin/pacstrap.sh ${chroot_path} $i
done

echo "==== Done pacstrap.sh ===="

curl -s -Lo ${chroot_path}/usr/bin/settings.sh https://raw.githubusercontent.com/ctlos/ctlos-sh/master/settings.sh
chmod +x ${chroot_path}/usr/bin/settings.sh
