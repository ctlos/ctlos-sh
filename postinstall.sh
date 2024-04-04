#!/bin/bash

## calamares shellprocess_postinstall.conf
# run chroot

clean_post() {
  local files_rm=(
    /etc/systemd/system/multi-user.target.wants/{choose-mirror.service,pacman-init.service,reflector.service}
  )
  local i
  for i in ${files_rm[*]}; do rm -rf $i; done
}

enable_dm() {
  rm /etc/systemd/system/display-manager.service
  [[ $(pacman -Qs sddm) ]] && systemctl enable sddm
  [[ $(pacman -Qs lightdm) ]] && systemctl enable lightdm
  [[ $(pacman -Qs lxdm) ]] && systemctl enable lxdm
  [[ $(pacman -Qs gdm) ]] && systemctl enable gdm
  # systemctl set-default graphical.target
}

# fix calamares 3.3.5, plasma 6 xsession
_conf() {
  if [ -f "/etc/sddm.conf" && -f "/usr/share/xsessions/plasmax11.desktop" ]; then
    sed -i "s/Session=.*/Session=plasmax11/" /etc/sddm.conf
  fi
}

clean_post
enable_dm
_conf

rm /usr/local/bin/postinstall.sh
