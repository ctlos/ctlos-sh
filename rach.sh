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
# Определяем количество потоков
THREADS=$(nproc)

read -p "create username: " NEW_USER
read -sp "create password: " PASSWORD
echo
read -sp "confirm password: " C_PASSWORD
if [[ "$PASSWORD" != "$C_PASSWORD" ]]; then
  echo "Error: incorrect password"; exit 1
fi


### форматирование, создание разделов и монтирование
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


### пакеты для установки
PKGS=(
base base-devel nano reflector openssh haveged
# linux-lts linux-lts-headers
linux linux-headers
linux-zen linux-zen-headers
# linux-cachyos linux-cachyos-headers
linux-firmware
amd-ucode
# grub
efibootmgr
os-prober
btrfs-progs
networkmanager
wget git rsync openbsd-netcat pv bash-completion less htop tmux zsh
starship zsh-autosuggestions fastfetch inxi micro bat
zip unzip unrar 7zip gzip bzip2 zlib hdparm nvme-cli
xorg-xkill xorg-xrdb
xf86-input-libinput xf86-input-vmmouse
# xf86-video-intel xf86-video-nouveau
# для vbox
xf86-video-vesa xf86-video-fbdev xf86-video-dummy
# встройка, старый драйвер только для X-сервера
xf86-video-amdgpu
pipewire pipewire-audio pipewire-pulse lib32-pipewire pipewire-alsa pipewire-jack
gst-plugin-pipewire wireplumber
zram-generator cpupower ananicy-cpp
# Графический мост
egl-wayland xorg-xwayland
# Для встройки
mesa lib32-mesa vulkan-mesa-layers vulkan-radeon lib32-vulkan-radeon vulkan-icd-loader lib32-vulkan-icd-loader
vkd3d lib32-vkd3d v4l2loopback-dkms
# nvidia-open-dkms nvidia-utils lib32-nvidia-utils nvidia-prime
plasma-login-manager plasma-meta fwupd xdg-desktop-portal-kde packagekit-qt6 kvantum
konsole dolphin kate ark ffmpegthumbs kwalletmanager kdeconnect gwenview
baloo kcalc partitionmanager
ttf-jetbrains-mono-nerd
firefox firefox-i18n-ru firefox-ublock-origin timeshift telegram-desktop
# brave-bin vlc qbittorrent
# Утилиты мониторинга и управления
nvtop btop openrgb piper amdgpu_top
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

# Ускоренный цикл: сначала проверяем наличие, потом ставим всё, что нашлось
VALID_PKGS=()
for pkg in "${PKGS[@]}"; do
    if pacman -Si "$pkg" >/dev/null 2>&1; then
        VALID_PKGS+=("$pkg")
    else
        echo "Пакет $pkg не найден в репозиториях, пропускаю..." | tee -a /tmp/log
    fi
done
pacstrap -K /mnt "${VALID_PKGS[@]}" 2>&1 | tee -a /tmp/log

genfstab -pU /mnt > /mnt/etc/fstab

echo "==== create settings.sh ===="
virt_d=$(systemd-detect-virt)
cat <<LOL >/mnt/settings.sh
mkdir -p /media

pacman -S --noconfirm --needed haveged
haveged -w 1024
pacman-key --init
pacman-key --populate
pkill haveged

sed -i '/Color/s/^#//g' /etc/pacman.conf
sed -i "/\[multilib\]/,/Include/"'s/^#//' /etc/pacman.conf
pacman -Syy --noconfirm


### сождание юзера и начальное конфигурирование
# usermod -p ${PASSWORD} root
echo "root:$PASSWORD" | chpasswd
useradd -m -g users -G "audio,video,input,adm,disk,log,network,scanner,storage,power,wheel" -s /usr/bin/zsh "$NEW_USER"
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
  sed -i "s/keyboard fsck/keyboard keymap/g" /etc/mkinitcpio.conf
else
  sed -i "s/^HOOKS=\(.*keyboard\)/HOOKS=\1 keymap/" /etc/mkinitcpio.conf
fi


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


### Ускоряем сборку: использовать все ядра и сжатие zstd
# Раскомментируем и выставляем максимальную скорость сборки
sed -i "s/#MAKEFLAGS=\"-j.*/MAKEFLAGS=\"-j$THREADS\"/" /etc/makepkg.conf
sed -i "s/COMPRESSZST=(zstd -c -T0 -)/COMPRESSZST=(zstd -c -T0 - --threads=0)/" /etc/makepkg.conf
sed -i '/^OPTIONS=/s/\([^!]\)debug\b/\1!debug/' /etc/makepkg.conf


### Установка пакетов из AUR
cd /home/$NEW_USER
sudo -u $NEW_USER git clone https://aur.archlinux.org/yay-bin.git
cd yay-bin
sudo -u $NEW_USER makepkg -sr --noconfirm
pacman -U --noconfirm --needed \$(ls *.pkg.tar.zst | grep -v "debug")
cd ~/ && rm -rf /home/$NEW_USER/yay-bin


### zsh config
cat <<'EOF' >/home/$NEW_USER/.zshrc
#!/usr/bin/zsh
# [[ -z \$DISPLAY && \$XDG_VTNR -eq 1 ]] && exec startx &> /dev/null

export PATH=\$HOME/.bin:\$HOME/.local/bin:\$PATH

export HISTFILE=~/.zhistory
export HISTSIZE=3000
export SAVEHIST=3000

autoload -Uz compinit
for dump in ~/.zcompdump(N.mh+24); do
  compinit
done
compinit -C

[[ -e /usr/share/zsh/plugins/fast-syntax-highlighting/fast-syntax-highlighting.plugin.zsh ]] && \
  source /usr/share/zsh/plugins/fast-syntax-highlighting/fast-syntax-highlighting.plugin.zsh

[[ -e /usr/share/zsh/plugins/zsh-autosuggestions/zsh-autosuggestions.zsh ]] && \
  source /usr/share/zsh/plugins/zsh-autosuggestions/zsh-autosuggestions.zsh

## ohmyzsh
if [[ -d /usr/share/oh-my-zsh ]]; then
  export ZSH="/usr/share/oh-my-zsh"
  ZSH_THEME="af-magic"
  DISABLE_AUTO_UPDATE="true"
  ZSH_TMUX_AUTOSTART="false"
  plugins=()
  ZSH_CACHE_DIR=\$HOME/.cache/oh-my-zsh
  [[ ! -d \$ZSH_CACHE_DIR ]] && mkdir -p \$ZSH_CACHE_DIR
  [[ -e \$ZSH/oh-my-zsh.sh ]] && source \$ZSH/oh-my-zsh.sh
else
  eval "\$(starship init zsh)"
fi
EOF
sudo chown -R $NEW_USER:users /home/$NEW_USER


### blacklist modules
cat <<EOF >/etc/modprobe.d/blacklist.conf
# Отключаем аппаратные сторожевые таймеры для снижения задержек
blacklist iTCO_wdt
blacklist iTCO_vendor_support
blacklist sp5100_tco
EOF


### параметры ядра
cat <<'EOF' >/etc/modprobe.d/nvidia.conf
# Wayland и консоль
options nvidia_drm modeset=1 fbdev=1
# Производительность и отсутствие статтеров
options nvidia NVreg_UsePageAttributeTable=1
options nvidia NVreg_InitializeSystemMemoryAllocations=0
options nvidia NVreg_DynamicPowerManagement=0x02
# Жесткая фиксация частот (PowerMizer)
options nvidia NVreg_RegistryDwords="PowerMizerEnable=0x1; PerfLevelSrc=0x3322; PowerMizerDefaultAC=0x1"
# MSI для снижения задержек шины
options nvidia NVreg_EnableMSI=1
# Отключаем сохранение видеопамяти при саспенде (убирает артефакты после пробуждения)
options nvidia NVreg_PreserveVideoMemoryAllocations=1
# Отключаем засыпание звуковой карты (убирает щелчки)
options snd_hda_intel power_save=0
options snd_hda_intel power_save_controller=N
EOF


### config zram-generator
cat <<'EOF' >/etc/systemd/zram-generator.conf
[zram0]
zram-size = 16384
compression-algorithm = lz4px
swap-priority = 100
fs-type = swap
EOF


### sysctl правила
## Настройка ядра (sysctl) для тяжелых игр:

cat <<'EOF' >/etc/sysctl.d/99-gaming.conf
# vm.swappiness = 10
### только с zram 180, без 10
vm.swappiness = 180
vm.page-cluster = 0
vm.vfs_cache_pressure = 50
vm.watermark_boost_factor = 0
vm.watermark_scale_factor = 125
# Лимиты для Proton и тяжелых движков
vm.max_map_count = 2147483647
net.core.default_qdisc = fq
net.ipv4.tcp_congestion_control = bbr
net.ipv4.tcp_fastopen = 3
# Это позволит TCP-соедниениям динамически расширяться
net.core.rmem_max = 25165824
net.core.wmem_max = 25165824
net.ipv4.tcp_rmem = 4096 87380 25165824
net.ipv4.tcp_wmem = 4096 65536 25165824
net.core.netdev_max_backlog = 5000
# Байтовый контроль записи
# (64 МБ): Как только в памяти накопится всего 64 МБ данных для записи,
# система начнет потихоньку сбрасывать их на NVMe
vm.dirty_background_bytes = 67108864
# (256 МБ): Это жесткий лимит. Больше 256 МБ «грязных» данных в ОЗУ не накопится
vm.dirty_bytes = 268435456
# Время в сотых долях секунды, через которое данные в ОЗУ считаются "старыми" и должны быть записаны
vm.dirty_expire_centisecs = 500
# Интервал проверки (в сотых долях секунды)
vm.dirty_writeback_centisecs = 300
# Отключение Watchdog
kernel.nmi_watchdog = 0
# Это уберет лишний мусор из консоли при загрузке
kernel.printk = 3 3 3 3
EOF

sysctl --system


### Модули ядра

cat <<'EOF' >/etc/modules-load.d/gaming-performance.conf
# Управление питанием и частотами процессора AMD
amd_pstate
# Поддержка работы сенсоров (мониторинг в MangoHud)
nct6775
# или k10temp (зависит от материнки, лучше оба)
k10temp
# Виртуализация (для работы эмуляторов/Docker/Wayland без задержек)
kvm_amd
# Драйверы NVIDIA (загружаем заранее для Gamescope/Wayland)
nvidia
nvidia_modeset
nvidia_uvm
nvidia_drm
# Оптимизация сетевых протоколов (если используешь специфические фильтры)
tcp_bbr
EOF


### Udev правила
cat <<'EOF' >/etc/udev/rules.d/80-nvidia-pm.rules
# Запрещаем видеокарте уходить в глубокий сон (D3), чтобы не было фризов при просыпании
ACTION=="add", SUBSYSTEM=="pci", ATTR{vendor}=="0x10de", ATTR{class}=="0x030000", ATTR{power/control}="on"
EOF

cat <<'EOF' >/etc/udev/rules.d/60-ioschedulers.rules
# Отключаем энергосбережение контроллеров SATA для исключения задержек
ACTION=="add", SUBSYSTEM=="scsi_host", KERNEL=="host*", ATTR{link_power_management_policy}="max_performance"
# правило для (HDD), которое окончательно запрещает им тупить и засыпать
ACTION=="add|change", KERNEL=="sd[a-z]", ATTR{queue/rotational}=="1", ATTRS{id/bus}=="ata", RUN+="/usr/bin/hdparm -B 254 -S 0 /dev/%k"
# HDD: Используем BFQ для плавности
ACTION=="add|change", KERNEL=="sd[a-z]*", ATTR{queue/rotational}=="1", ATTR{queue/scheduler}="bfq"
# SSD (SATA): Kyber — баланс скорости и задержек
ACTION=="add|change", KERNEL=="sd[a-z]*|mmcblk[0-9]*", ATTR{queue/rotational}=="0", ATTR{queue/scheduler}="kyber"
# NVMe (Samsung 9100 PRO): Прямой доступ без планировщика
# Мы используем 'none', чтобы дать контроллеру SSD полную свободу
ACTION=="add|change", KERNEL=="nvme[0-9]*", ATTR{queue/rotational}=="0", ATTR{queue/scheduler}="none", ATTR{queue/nr_requests}="1024"
EOF

cat <<'EOF' >/etc/udev/rules.d/40-timer-permissions.rules
# для оптимизации прерываний реального времени
KERNEL=="rtc0", GROUP="audio"
KERNEL=="hpet", GROUP="audio"
EOF

udevadm control --reload-rules


### NetworkManager
cat <<'EOF' >/etc/NetworkManager/conf.d/99-gaming.conf
[device]
# Отключаем случайную генерацию MAC-адресов (ускоряет подключение к роутеру)
wifi.scan-rand-mac-address=no

[connection]
# Отключаем IPv6, если твой провайдер его не использует (убирает лишние запросы)
ipv6.method=ignore
# Настройка для Wi-Fi (если используешь чип MediaTek/Realtek на X870E)

[wifi]
# Отключаем агрессивное сканирование сетей в фоновом режиме.
# Это убирает резкие скачки пинга (lag spikes) каждые пару минут.
powersave=2
EOF


### Снизь задержку звука PipeWire
mkdir -p /etc/pipewire/pipewire.conf.d

cat <<'EOF' >/etc/pipewire/pipewire.conf.d/99-low-latency.conf
context.properties = {
    default.clock.rate          = 48000
    default.clock.allowed-rates  = [ 44100 48000 88200 96000 ]
    default.clock.quantum       = 128
    default.clock.min-quantum   = 64
    default.clock.max-quantum   = 1024
}
EOF


### лимиты
cat <<'EOF' >/etc/security/limits.d/99-gaming.conf
# Лимиты на файлы
* soft nofile 524288
* hard nofile 1048576
# Приоритеты и память
* soft memlock unlimited
* hard memlock unlimited
* -    nice    -20
# Аудио реального времени
@audio - rtprio 99
@audio - memlock unlimited
EOF


### службы
systemctl enable sshd
systemctl enable NetworkManager
# systemctl enable sddm
systemctl enable plasmalogin
systemctl enable power-profiles-daemon
systemctl enable ananicy-cpp
systemctl enable bluetooth
# systemctl enable avahi-daemon


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

# zen
cat <<EOF >/boot/loader/entries/arch-zen.conf
title Rach Linups (zen)
linux /vmlinuz-linux-zen
initrd /amd-ucode.img
initrd /initramfs-linux-zen.img
options root=UUID=$root_uuid $systemd_flags rw nowatchdog
# options root=UUID=$root_uuid $systemd_flags rw nowatchdog nmi_watchdog=0 nvidia_drm.modeset=1 nvidia_drm.fbdev=1 amd_pstate=active mitigations=off tsc=reliable clocksource=tsc split_lock_detect=off usbcore.autosuspend=-1
EOF

# Конфиг для обычного ядра (arch linux)
cat <<EOF >/boot/loader/entries/arch.conf
title Rach Linups (Arch Kernel)
linux /vmlinuz-linux
initrd /amd-ucode.img
initrd /initramfs-linux.img
options root=UUID=$root_uuid $systemd_flags rw
EOF

fi

echo ">>> System Setup Complete"
LOL

chmod +x /mnt/settings.sh
arch-chroot /mnt /bin/bash -c /settings.sh 2>&1 | tee -a /tmp/log
rm /mnt/settings.sh

echo "==== Done settings.sh ===="

if read -re -p "arch-chroot /mnt? [y/N]: " ans && [[ $ans == 'y' || $ans == 'Y' ]]; then
  arch-chroot /mnt
else
  umount -lR /mnt
fi
# swapoff $S_DISK

echo ">>> less /tmp/log"
echo ""
cat <<EOF
>>> reboot > recomends install: yay -S --noconfirm
oh-my-zsh-git
zsh-fast-syntax-highlighting
cachyos-ananicy-rules-git
vkbasalt lib32-vkbasalt
proton-ge-custom-bin
protonup-qt-bin
dxvk-bin
heroic-games-launcher-bin
EOF

echo "==== Finish Him ===="