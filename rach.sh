#!/bin/bash
# Install script archlinux
# https://raw.githubusercontent.com/ctlos/ctlos-sh/master/rach.sh

# curl -LO kutt.to/rach
# nano rach.sh
# sudo sh rach.sh

HOST_NAME=rach
# btrfs || ext4
FS_TYPE=btrfs
# systemd-boot || grub-efi || grub
BOOT_LOADER=systemd-boot

# Check for root
if [[ $EUID -ne 0 ]]; then
  echo "run root"; exit 1
fi

read -p "create username: " NEW_USER
read -sp "create password: " PASSWORD
echo
read -sp "confirm password: " C_PASSWORD
if [[ "$PASSWORD" != "$C_PASSWORD" ]]; then
  echo "Error: incorrect password"; exit 1
fi

# cfdisk -z /dev/sda
lsblk -d
echo "sda,vda,nvme..?"
read -p "Disk?: " I_DISK
DISK=/dev/$I_DISK
if [[ ! $(lsblk -d | grep $I_DISK) ]]; then
  echo "Error: incorrect disk."; exit 1
fi

dd if=/dev/zero of=${DISK} status=progress bs=4096 count=256

# mklabel msdos || mklabel gpt
parted ${DISK} << EOF
mklabel gpt
mkpart primary 1MiB 300MiB
set 1 boot on
mkpart primary 300MiB 100%
quit
EOF

B_DISK=${DISK}1
R_DISK=${DISK}2
S_DISK=${DISK}3
H_DISK=${DISK}4

## swap
# mkswap $S_DISK -L swap
# swapon $S_DISK

if [[ "$FS_TYPE" == "btrfs" ]]; then
  mkfs.btrfs -f -L "root" $R_DISK
  yes | mkfs.fat -F32 $B_DISK
  mount $R_DISK /mnt
  btrfs subvolume create /mnt/@
  btrfs subvolume create /mnt/@home
  btrfs subvolume create /mnt/@cache
  btrfs subvolume create /mnt/@snapshots
  umount -R /mnt
  mount -o compress=zstd:1,ssd,discard=async,noatime,subvol=@ $R_DISK /mnt
  mkdir -p /mnt/{boot,home,var/cache,.snapshots,games}
  mount -o compress=zstd:1,ssd,discard=async,noatime,subvol=@home $R_DISK /mnt/home
  mount -o compress=zstd:1,ssd,discard=async,noatime,subvol=@cache $R_DISK /mnt/var/cache
  mount -o compress=zstd:1,ssd,discard=async,subvol=@snapshots $R_DISK /mnt/.snapshots
  mount $B_DISK /mnt/boot
  # Монтируем раздел с играми (Ext4)
  # mount -o noatime,lazytime,commit=60,data=ordered /dev/nvme0n1p3 /mnt/mnt/games
  if [[ "$BOOT_LOADER" == "systemd-boot" ]]; then
    systemd_flags="rootflags=subvol=/@ rootfstype=btrfs"
  else
    systemd_flags=""
  fi
elif [[ "$FS_TYPE" == "ext4" ]]; then
  yes | mkfs.ext4 $R_DISK -L root
  yes | mkfs.fat -F32 $B_DISK
  # yes | mkfs.ext4 $H_DISK -L home
  mount $R_DISK /mnt
  mkdir /mnt/boot
  mount $B_DISK /mnt/boot
  # mkdir /mnt/home
  # mount $H_DISK /mnt/home
else
  echo "fs type"; exit 1
fi

root_uuid=$(lsblk -no UUID ${R_DISK})

## https://ipapi.co/timezone | http://ip-api.com/line?fields=timezone | https://ipwhois.app/line/?objects=timezone
time_zone=$(curl -s https://ipinfo.io/timezone)
timedatectl set-timezone $time_zone

reflector --verbose -p "https,http" --sort rate -l 20 -f 10 --threads 5 --save /etc/pacman.d/mirrorlist
# reflector --verbose -p "https,http" -c "ru,kz,pl,de,$(curl -s https://ipinfo.io/country)" --sort rate -l 20 -f 10 --threads 5 --save /etc/pacman.d/mirrorlist

PKGS=(
base base-devel nano reflector openssh
# linux-lts linux-lts-headers
linux linux-headers
linux-zen linux-zen-headers
# linux-cachyos linux-cachyos-headers
linux-firmware
amd-ucode
# intel-ucode
# lvm2
# grub
efibootmgr
os-prober
btrfs-progs
# arch-install-scripts
# dhcpcd netctl iwd
networkmanager
wget git rsync gnu-netcat pv bash-completion htop tmux zsh
zip unzip unrar p7zip gzip bzip2 zlib hdparm nvme-cli
xorg-xkill xorg-xrdb
xf86-input-libinput xf86-input-vmmouse
# xf86-video-fbdev xf86-video-dummy
# xf86-video-intel xf86-video-amdgpu xf86-video-ati xf86-video-nouveau
xf86-video-amdgpu xf86-video-vesa
pipewire pipewire-audio pipewire-pulse lib32-pipewire pipewire-alsa pipewire-jack
gst-plugin-pipewire wireplumber
zram-generator cpupower ananicy-cpp
# Графический мост
egl-wayland xorg-xwayland
# Для встройки
mesa lib32-mesa vulkan-radeon lib32-vulkan-radeon vulkan-icd-loader lib32-vulkan-icd-loader
libva-mesa-driver lib32-libva-mesa-driver mesa-vdpau lib32-mesa-vdpau
vkd3d lib32-vkd3d v4l2loopback-dkms
# nvidia-open-dkms nvidia-utils lib32-nvidia-utils nvidia-prime
plasma-login-manager plasma-meta fwupd xdg-desktop-portal-kde packagekit-qt6 kvantum
konsole dolphin ark ffmpegthumbs kwalletmanager kdeconnect gwenview
baloo kcalc partitionmanager
ttf-jetbrains-mono-nerd
firefox firefox-i18n-ru firefox-ublock-origin timeshift telegram-desktop
# brave-bin vlc qbittorrent
# Утилиты мониторинга и управления
nvtop btop openrgb piper amdgpu_top gwe
# game
steam lutris
# Нужен для работы nice с отрицательными значениями (приоритет процесса) без root-прав
libcap
# Содержит taskset (привязка к ядрам). Обычно уже есть в системе, но проверь
util-linux
# Содержит powerprofilesctl для переключения режимов энергопотребления
power-profiles-daemon
# Отключает энергосбережение, повышает приоритет процесса и меняет "губернатор" CPU на performance
gamemode lib32-gamemode
# Микро-композитор от Valve. Маст-хэв для 240Hz. Он позволяет запускать игру в изолированном слое
gamescope
# Лучший оверлей. Показывает FPS, температуру, загрузку конкретных ядер и использование VRAM
mangohud lib32-mangohud
)

for i in "${PKGS[@]}"; do
  pacstrap -K /mnt $i 2>&1 | tee -a /tmp/log
done

genfstab -pU /mnt > /mnt/etc/fstab

echo "==== create settings.sh ===="
virt_d=$(systemd-detect-virt)
cat <<LOL >/mnt/settings.sh
pacman-key --init
pacman-key --populate

sed -i '/Color/s/^#//g' /etc/pacman.conf
sed -i "/\[multilib\]/,/Include/"'s/^#//' /etc/pacman.conf
pacman -Syy --noconfirm


### сождание юзера и начальное конфигурирование
# usermod -p ${PASSWORD} root
echo "root:$PASSWORD" | chpasswd
glist="audio,video,input,adm,disk,log,network,scanner,storage,power,wheel"
useradd -m -g users -G $glist -s /usr/bin/zsh "$NEW_USER"
# usermod -p ${PASSWORD} "$NEW_USER"
echo "$NEW_USER:$PASSWORD" | chpasswd

echo "%wheel ALL=(ALL) ALL" >> /etc/sudoers
# echo "%wheel ALL=(ALL:ALL) NOPASSWD: ALL" > /etc/sudoers.d/wheel
echo $HOST_NAME > /etc/hostname
ln -sf /usr/share/zoneinfo/$time_zone /etc/localtime
hwclock --systohc --utc
timedatectl set-ntp true

echo "en_US.UTF-8 UTF-8" > /etc/locale.gen
echo "ru_RU.UTF-8 UTF-8" >> /etc/locale.gen
locale-gen
echo "LANG=ru_RU.UTF-8" > /etc/locale.conf
echo "KEYMAP=ru" > /etc/vconsole.conf
echo "FONT=cyr-sun16" >> /etc/vconsole.conf


### rm fsck btrfs
# sed -i "s/^HOOKS=\(.*block\)/HOOKS=\1 lvm2 ventoy/" /etc/mkinitcpio.conf
# sed -i "s/keyboard fsck/keyboard keymap fsck/g" /etc/mkinitcpio.conf
## btrfs rm fsck
if [[ "$FS_TYPE" == "btrfs" ]]; then
  sed -i "s/filesystems fsck/filesystems/g" /etc/mkinitcpio.conf
fi
mkinitcpio -P


### если в виртуалке
if [[ "$virt_d" == "oracle" ]]; then
  echo "Virtualbox"
  pacman -S --noconfirm --needed virtualbox-guest-utils
  systemctl enable vboxservice
  usermod -a -G vboxsf ${NEW_USER}
elif [[ "$virt_d" == "vmware" ]]; then
  echo
else
  echo "Virt $virt_d"
fi


### загрузчик
if [[ "$BOOT_LOADER" == "grub-efi" ]]; then
grub-install --target=x86_64-efi --efi-directory=/boot
# sed -i -e 's/^GRUB_TIMEOUT=.*$/GRUB_TIMEOUT=0/' /etc/default/grub
sed -i '/GRUB_DISABLE_OS_PROBER/s/^#//g' /etc/default/grub
grub-mkconfig -o /boot/grub/grub.cfg
elif [[ "$BOOT_LOADER" == "grub" ]]; then
grub-install $DISK
grub-mkconfig -o /boot/grub/grub.cfg
else
bootctl install
cat <<EOF >/boot/loader/loader.conf
default arch-zen.conf
timeout 3
editor 1
console-mode max
EOF
cat <<EOF >/boot/loader/entries/arch-zen.conf
title Rach Linups
linux /vmlinuz-linux-zen
initrd /amd-ucode.img
initrd /initramfs-linux-zen.img
options root=UUID=$root_uuid $systemd_flags rw
# options root=UUID=$root_uuid $systemd_flags rw nowatchdog nmi_watchdog=0 nvidia_drm.modeset=1 nvidia_drm.fbdev=1 amd_pstate=active mitigations=off tsc=reliable clocksource=tsc split_lock_detect=off usbcore.autosuspend=-1
EOF
fi


### hosts
cat <<EOF >/etc/hosts
127.0.0.1       localhost
::1             localhost
127.0.1.1       $HOST_NAME.localdomain $HOST_NAME
EOF


### сетевые конфиги
cat <<EOF >/etc/systemd/network/20-ethernet.network
[Match]
Name=en*
Name=eth*

[Network]
DHCP=yes
EOF

cat <<EOF >/etc/systemd/network/20-wireless.network
[Match]
Type=wlan

[Network]
DHCP=yes
EOF


### установка yay
cd /home/$NEW_USER
sudo -u $NEW_USER git clone https://aur.archlinux.org/yay-bin.git
cd yay-bin
sudo -u $NEW_USER makepkg -sri --noconfirm


### службы
systemctl enable sshd
systemctl enable NetworkManager
systemctl enable power-profiles-daemon

# systemctl enable systemd-networkd
# systemctl enable systemd-resolved

# systemctl enable sddm
systemctl enable plasmalogin

echo "==== System Setup Complete ===="
LOL

chmod +x /mnt/settings.sh
arch-chroot /mnt /bin/bash -c /settings.sh 2>&1 | tee -a /tmp/log
rm /mnt/settings.sh

echo "==== Done settings.sh ===="

if read -re -p "arch-chroot /mnt? [y/N]: " ans && [[ $ans == 'y' || $ans == 'Y' ]]; then
  arch-chroot /mnt
else
  umount -R /mnt
fi
# swapoff $S_DISK

echo "less /tmp/log"

echo "==== Finish Him ===="