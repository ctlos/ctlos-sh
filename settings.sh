#!/bin/bash

## calamares shellprocess_settings.conf
# run chroot
# add ctlos repo

curl -sO https://raw.githubusercontent.com/ctlos/ctlos-sh/master/strap.sh
sh strap.sh
rm strap.sh

rm /usr/local/bin/settings.sh
