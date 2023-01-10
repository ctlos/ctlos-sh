#!/bin/bash

## calamares shellprocess_settings.conf
# run chroot
# add ctlos repo

curl -s -o /usr/local/bin/strap.sh -L https://raw.githubusercontent.com/ctlos/ctlos-sh/master/strap.sh
sh /usr/local/bin/strap.sh
rm /usr/local/bin/strap.sh

mkdir /media

cat <<LOL >>/etc/pacman.d/gnupg/gpg.conf
keyserver hkps://hkps.pool.sks-keyservers.net:443
keyserver hkp://ipv4.pool.sks-keyservers.net:11371
keyserver hkp://pgp.mit.edu
keyserver hkp://keys.gnupg.net
keyserver hkp://keyserver.ubuntu.com
LOL

rm /usr/local/bin/settings.sh
