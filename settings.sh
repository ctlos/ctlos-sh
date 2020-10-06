#!/bin/bash

reflector -a 12 -l 30 -f 30 -p https --sort rate --save /etc/pacman.d/mirrorlist

curl -LO git.io/strap.sh
sh strap.sh
rm strap.sh

echo "==== Done settings.sh ===="

rm /usr/bin/settings.sh
