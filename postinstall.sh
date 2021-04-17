#!/bin/bash

## calamares shellprocess_postinstall.conf
# run chroot

enable_dm() {
  rm /etc/systemd/system/display-manager.service
  [[ $(pacman -Qs sddm) ]] && systemctl enable sddm
  [[ $(pacman -Qs lightdm) ]] && systemctl enable lightdm
  [[ $(pacman -Qs lxdm) ]] && systemctl enable lxdm
  [[ $(pacman -Qs gdm) ]] && systemctl enable gdm
  # systemctl set-default graphical.target
}
enable_dm

rm /usr/local/bin/postinstall.sh
