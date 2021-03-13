#!/bin/bash

chroot_path=$(cat /tmp/chroot_path.tmp)

[[ -d $chroot_path ]] || { echo "error: chroot path"; exit; }

if [[ $(command -v reflector) && $(command -v curl) ]]; then
  reflector -a 12 -l 30 -f 30 -p https,http --sort rate --save /etc/pacman.d/mirrorlist
else
  pacman -S reflector curl --noconfirm
  reflector -a 12 -l 30 -f 30 -p https,http --sort rate --save /etc/pacman.d/mirrorlist
fi

if [[ $(command -v pacstrap) ]]; then
  pacman -S arch-install-scripts --noconfirm
fi

if [[ ! -f "/usr/bin/pacstrap.sh" ]]; then
sed -e '/chroot_add_mount proc/d' \
  -e '/chroot_add_mount sys/d' \
  -e '/ignore_error chroot_maybe_add_mount/d' \
  -e '/chroot_add_mount udev/d' \
  -e '/chroot_add_mount devpts/d' \
  -e '/chroot_add_mount shm/d' \
  -e '/chroot_add_mount \/run/d' \
  -e '/chroot_add_mount tmp/d' \
  -e '/efivarfs \"/d' /usr/bin/pacstrap >/usr/bin/pacstrap.sh
chmod +x /usr/bin/pacstrap.sh
fi

PKGS=(
base sudo grub reflector lsb-release nano iwd haveged
gnu-netcat rsync zsh
)

/usr/bin/pacstrap.sh ${chroot_path} ${PKGS[@]}

echo "==== Done pacstrap.sh ===="

cat <<LOL >${chroot_path}/settings.sh
# curl -LO git.io/strap.sh
curl -sO https://raw.githubusercontent.com/ctlos/ctlos-sh/master/strap.sh
sh strap.sh
rm strap.sh

# pacman-key --init
# pacman-key --populate
# pacman -Syy --noconfirm
LOL

chmod +x ${chroot_path}/settings.sh
arch-chroot ${chroot_path} /bin/bash -c /settings.sh
rm ${chroot_path}/settings.sh

echo "==== Done settings.sh ===="
