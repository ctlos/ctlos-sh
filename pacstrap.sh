#!/bin/bash

## calamares module baseinstall

chroot_path=$(cat /tmp/chroot_path.tmp)

[[ -d $chroot_path ]] || { echo "error: chroot path"; exit; }

if [[ $(command -v reflector) && $(command -v curl) ]]; then
  reflector -a 12 -l 15 -p https,http --sort rate --save /etc/pacman.d/mirrorlist
else
  pacman -S reflector curl --noconfirm
  reflector -a 12 -l 15 -p https,http --sort rate --save /etc/pacman.d/mirrorlist
fi

if [[ $(command -v pacstrap) ]]; then
  pacman -S arch-install-scripts --noconfirm
fi

if [[ ! -f "/usr/bin/pacstrap.sh" ]]; then
# sed -e '/chroot_add_mount proc/d' \
#   -e '/chroot_add_mount sys/d' \
#   -e '/ignore_error chroot_maybe_add_mount/d' \
#   -e '/chroot_add_mount udev/d' \
#   -e '/chroot_add_mount devpts/d' \
#   -e '/chroot_add_mount shm/d' \
#   -e '/chroot_add_mount \/run/d' \
#   -e '/chroot_add_mount tmp/d' \
#   -e '/efivarfs \"/d' /usr/bin/pacstrap >/usr/bin/pacstrap.sh
curl -s -Lo /usr/bin/pacstrap.sh https://raw.githubusercontent.com/ctlos/ctlos-sh/master/pacstrap_bak
chmod +x /usr/bin/pacstrap.sh
fi

_vbox() {
  result=$(systemd-detect-virt)
  if [ $result = "oracle" ]; then
    vbox_pkgs="virtualbox-guest-utils virtualbox-guest-dkms"
  elif [ $result = "vmware" ]; then
    vbox_pkgs=""
  else
    vbox_pkgs=""
  fi
}
_vbox

PKGS=(
base sudo grub reflector lsb-release nano iwd haveged
gnu-netcat rsync zsh
)

/usr/bin/pacstrap.sh ${chroot_path} ${PKGS[@]} $vbox_pkgs

curl -s -o ${chroot_path}/usr/local/bin/settings.sh -L https://raw.githubusercontent.com/ctlos/ctlos-sh/master/settings.sh
chmod +x ${chroot_path}/usr/local/bin/settings.sh

curl -s -o ${chroot_path}/usr/local/bin/system.sh -L https://raw.githubusercontent.com/ctlos/ctlos-sh/master/system.sh
chmod +x ${chroot_path}/usr/local/bin/system.sh

echo "==== Done pacstrap.sh ===="
