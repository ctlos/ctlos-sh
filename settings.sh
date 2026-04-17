#!/bin/bash

## calamares shellprocess_settings.conf
# run chroot

echo "=== add repo archlinuxcn ==="
pacman -U --noconfirm https://repo.archlinuxcn.org/x86_64/archlinuxcn-keyring-20250506-1-any.pkg.tar.zst
echo -e '\n\n[archlinuxcn]\nServer = https://repo.archlinuxcn.org/$arch\n' | tee -a /etc/pacman.conf >/dev/null
tail -n 5 /etc/pacman.conf
pacman -Syy

mkdir /media

haveged -w 1024
pacman-key --init
pacman-key --populate
pkill haveged

cat <<LOL >>/etc/pacman.d/gnupg/gpg.conf
keyserver = keys.openpgp.org
keyserver = keyserver.ubuntu.com
LOL

rm /usr/local/bin/settings.sh
