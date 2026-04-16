#!/bin/bash

## calamares shellprocess_postinstall.conf
# run chroot

_clean_post() {
  local files_rm=(
    /etc/systemd/system/multi-user.target.wants/{choose-mirror.service,pacman-init.service,reflector.service}
  )
  local i
  for i in ${files_rm[*]}; do rm -rf $i; done
}

_enable_dm() {
  rm /etc/systemd/system/display-manager.service
  [[ $(pacman -Qs gdm) ]] && systemctl enable gdm
  [[ $(pacman -Qs sddm) ]] && systemctl enable sddm
  [[ $(pacman -Qs lightdm) ]] && systemctl enable lightdm
  [[ $(pacman -Qs lxdm) ]] && systemctl enable lxdm
  # systemctl set-default graphical.target
}

_conf() {
  # fix calamares 3.3.5, plasma 6 xsession
  if [ -f "/etc/sddm.conf" && -f "/usr/share/xsessions/plasmax11.desktop" ]; then
    sed -i "s/Session=.*/Session=plasmax11/" /etc/sddm.conf
  fi

  if [ ! -f "/usr/share/xsessions/plasmax11.desktop" && ! -f "/etc/gdm/custom.conf" ]; then
    echo "QT_QPA_PLATFORMTHEME=qt5ct" > /etc/environment
    echo "#QT_STYLE_OVERRIDE=kvantum" >> /etc/environment
    echo "GTK_THEME=Ctlos-Dark" >> /etc/environment
  fi

  if command -v gdm >/dev/null; then
    pacman -Rnsdd sddm --noconfirm
  fi

  result=$(systemd-detect-virt)
  if [ $result = "oracle" ]; then
    systemctl enable vboxservice
  fi
}

_clean_post
_enable_dm
_conf

rm /usr/local/bin/postinstall.sh
