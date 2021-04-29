#!/bin/bash

## calamares shellprocess_settings.conf
# run chroot
# add ctlos repo

curl -sO https://raw.githubusercontent.com/ctlos/ctlos-sh/master/strap.sh
sh strap.sh
rm strap.sh

mkdir /media

cat <<LOL >>/etc/pacman.d/gnupg/gpg.conf
keyserver hkps://hkps.pool.sks-keyservers.net:443
keyserver hkp://ipv4.pool.sks-keyservers.net:11371
keyserver hkp://pgp.mit.edu
keyserver hkp://keys.gnupg.net
LOL

rm /usr/local/bin/settings.sh
