#!/bin/bash

## calamares shellprocess_settings.conf
# run chroot

echo "[+] Updating archlinuxcn-keyring..."
pacman -Sy --noconfirm archlinuxcn-keyring || {
    echo "[-] Failed to update keyring, trying full refresh..."
    pacman -Syyu --noconfirm archlinuxcn-keyring
}

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
