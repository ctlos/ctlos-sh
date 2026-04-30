#!/bin/bash
# set -euo pipefail

## Install script archlinux
# https://raw.githubusercontent.com/ctlos/ctlos-sh/master/rach.sh

# curl -LO kutt.to/rach
# nano rach.sh
# sudo sh rach.sh
## run ENV
# sudo HOST_NAME=my-pc sh rach

exec > >(tee -a /tmp/install.log) 2>&1

# === CONFIG ===
: "${HOST_NAME:=arch}"
: "${FS_TYPE:=btrfs}"
# grub-efi | grub | systemd-boot
: "${BOOT_LOADER:=grub-efi}"
: "${THREADS:=$(nproc)}"
# quiet
KERNEL_PARAMS="loglevel=3 nowatchdog nmi_watchdog=0 nvidia_drm.modeset=1 nvidia_drm.fbdev=1 mitigations=off tsc=reliable clocksource=tsc split_lock_detect=off usbcore.autosuspend=-1"

# === UTILS ===
log() { echo "[$(date '+%H:%M:%S')] $*"; }
die() { log "ERROR: $*"; exit 1; }
check_root() { [[ $EUID -eq 0 ]] || die "Run as root"; }


# === INPUT ===
check_root
read -p "Create username: " NEW_USER
read -sp "Create password: " PASSWORD; echo
read -sp "Confirm password: " C_PASSWORD; echo
[[ "$PASSWORD" == "$C_PASSWORD" ]] || die "Passwords mismatch"

log "Select disk (lsblk -d):"
lsblk -d
read -p "Disk name (e.g. sda | vda | nvme0n1 | ...): " I_DISK
DISK="/dev/$I_DISK"
lsblk -d | grep -q "$I_DISK" || die "Disk $I_DISK not found"

# === PREPARE DISK ===
log "Wiping disk header..."
dd if=/dev/zero of="$DISK" bs=4096 count=256 status=progress

log "Creating GPT partitions..."
parted ${DISK} << EOF
mklabel gpt
mkpart primary 1MiB 1025MiB
set 1 esp on
mkpart primary 1025MiB 501GiB
mkpart primary 501GiB 100%
quit
EOF
sync && sleep 2

if [[ ${DISK} == *"nvme"* ]]; then P="p"; else P=""; fi
B_DISK="${DISK}${P}1"
R_DISK="${DISK}${P}2"
G_DISK="${DISK}${P}3"

# === FORMAT & MOUNT ===
if [[ "$FS_TYPE" == "btrfs" ]]; then
  mkfs.btrfs -f -L "ARCH_SYSTEM" "$R_DISK"
  yes | mkfs.fat -F32 "$B_DISK"
  yes | mkfs.ext4 -F -L "GAMES" "$G_DISK"
  mount "$R_DISK" /mnt
  btrfs subvolume create /mnt/{@,@home,@cache,@snapshots}
  umount /mnt

  BTRFS_OPTS="compress=zstd:1,ssd,discard=async,noatime"
  mount -o "$BTRFS_OPTS,subvol=@" "$R_DISK" /mnt
  mkdir -p /mnt/{boot,media/games,home,var/cache,.snapshots}
  mount -o "$BTRFS_OPTS,subvol=@home" "$R_DISK" /mnt/home
  mount -o "$BTRFS_OPTS,subvol=@cache" "$R_DISK" /mnt/var/cache
  mount -o "${BTRFS_OPTS//noatime/},subvol=@snapshots" "$R_DISK" /mnt/.snapshots
  # Монтируем раздел с играми (Ext4)
  mount -o noatime,lazytime,commit=60,data=ordered "$G_DISK" /mnt/media/games
  # --- УСЛОВИЕ ДЛЯ ЗАГРУЗЧИКА ---
  # раздел boot (fat32)
  [[ "$BOOT_LOADER" == "systemd-boot" ]] && SYSTEMD_FLAGS="rootflags=subvol=/@ rootfstype=btrfs" || SYSTEMD_FLAGS=""
  if [[ "$BOOT_LOADER" == "systemd-boot" ]]; then
    # Для systemd-boot монтируем прямо в /boot
    log "Configuring mount for systemd-boot (/boot)"
    mkdir -p /mnt/boot
    mount "$B_DISK" /mnt/boot
  elif [[ "$BOOT_LOADER" == "grub-efi" ]]; then
    # Для GRUB efi монтируем в /boot/efi
    log "Configuring mount for GRUB (/boot/efi)"
    mkdir -p /mnt/boot/efi
    mount "$B_DISK" /mnt/boot/efi
  else
    # Для GRUB монтируем в /boot
    log "Configuring mount for GRUB (/boot)"
    mkdir -p /mnt/boot
    mount "$B_DISK" /mnt/boot
  fi

elif [[ "$FS_TYPE" == "ext4" ]]; then
  yes | mkfs.ext4 -F -L root "$R_DISK"
  yes | mkfs.fat -F32 "$B_DISK"
  mount "$R_DISK" /mnt
  mkdir -p /mnt/{boot,media/games}
  mount "$B_DISK" /mnt/boot
  mount -o noatime,lazytime,commit=60,data=ordered "$G_DISK" /mnt/media/games
  SYSTEMD_FLAGS=""
else
  die "Unsupported FS_TYPE: $FS_TYPE"
fi

ROOT_UUID=$(lsblk -no UUID "$R_DISK")
TIME_ZONE=$(curl -s https://ipinfo.io/timezone)


# === MIRRORS & PACSTRAP ===
log "Updating mirrorlist..."
rm -rf /etc/pacman.d/hooks/*
reflector --verbose -p https,http --sort rate -l 20 -f 10 --threads 5 --save /etc/pacman.d/mirrorlist
pacman -Syy --noconfirm archlinux-keyring

log "Installing base packages..."
PKGS=(
base base-devel nano reflector openssh haveged
linux linux-headers
linux-zen linux-zen-headers
linux-firmware btrfs-progs
efibootmgr grub grub-btrfs os-prober
amd-ucode # intel-ucode
networkmanager # networkmanager-openconnect networkmanager-openvpn mobile-broadband-provider-info
## wifi: iwd | wpa_supplicant
wireless-regdb wireless_tools iwd
# modemmanager b43-fwcutter broadcom-wl
bluez bluez-utils bluez-libs
wget git rsync openbsd-netcat pv bash-completion less bat bottom
zsh starship zsh-autosuggestions fastfetch tmux inxi micro
zip unzip unrar 7zip gzip bzip2 zlib hdparm nvme-cli smartmontools
xorg-xkill xorg-xrdb xorg-xwayland
xf86-input-libinput
pipewire pipewire-audio pipewire-pulse lib32-pipewire pipewire-alsa pipewire-jack
gst-plugin-pipewire wireplumber
## vbox
# xf86-input-vmmouse xf86-video-vesa xf86-video-fbdev mesa lib32-mesa
## Для встройки
mesa lib32-mesa xf86-video-amdgpu vulkan-radeon lib32-vulkan-radeon
vulkan-mesa-layers vulkan-icd-loader lib32-vulkan-icd-loader
vkd3d lib32-vkd3d v4l2loopback-dkms amdgpu_top
## nvidia
nvidia-open-dkms nvidia-utils lib32-nvidia-utils nvidia-prime nvtop
## Графический мост nvidia
egl-wayland
zram-generator cpupower ananicy-cpp
ttf-jetbrains-mono-nerd
oh-my-zsh-git zsh-fast-syntax-highlighting
## kde
plasma-login-manager plasma-meta fwupd xdg-desktop-portal-kde packagekit-qt6 kvantum
konsole dolphin kate ark ffmpegthumbs kwalletmanager kdeconnect gwenview
baloo kcalc partitionmanager
ttf-jetbrains-mono-nerd
firefox firefox-i18n-ru firefox-ublock-origin timeshift telegram-desktop
# brave-bin vlc qbittorrent
## Утилиты мониторинга и управления
btop openrgb piper
## game
steam lutris
## Нужен для работы nice с отрицательными значениями (приоритет процесса) без root-прав
libcap
## Содержит taskset (привязка к ядрам). Обычно уже есть в системе, но проверь
util-linux
## Содержит powerprofilesctl для переключения режимов энергопотребления
power-profiles-daemon
## Отключает энергосбережение, повышает приоритет процесса и меняет "губернатор" CPU на performance
gamemode lib32-gamemode
## Микро-композитор от Valve. Маст-хэв для 240Hz. Он позволяет запускать игру в изолированном слое
gamescope
## Лучший оверлей. Показывает FPS, температуру, загрузку конкретных ядер и использование VRAM
mangohud lib32-mangohud
)

# Ускоренный цикл: сначала проверяем наличие, потом ставим всё, что нашлось
VALID_PKGS=()
for pkg in "${PKGS[@]}"; do
    if pacman -Si "$pkg" >/dev/null 2>&1; then
        VALID_PKGS+=("$pkg")
    else
        log "Warning: Package $pkg not found, skipping..."
    fi
done
pacstrap /mnt "${VALID_PKGS[@]}" || log "Some packages may have failed, continuing..."
genfstab -pU /mnt > /mnt/etc/fstab

# === POST-INSTALL SCRIPT (chroot) ===
cat <<CHROOT_SCRIPT >/mnt/post-install.sh
#!/bin/bash
# set -euo pipefail

# === ADD VAR TO CHROOT ===
NEW_USER="$NEW_USER"
PASSWORD="$PASSWORD"
HOST_NAME="$HOST_NAME"
TIME_ZONE="$TIME_ZONE"
FS_TYPE="$FS_TYPE"
KERNEL_PARAMS="$KERNEL_PARAMS"
BOOT_LOADER="$BOOT_LOADER"
ROOT_UUID="$ROOT_UUID"
SYSTEMD_FLAGS="$SYSTEMD_FLAGS"
THREADS="$THREADS"

log() { echo "[\$(date '+%H:%M:%S')] \$*"; }


# === BASIC SETUP ===
mkdir -p /media
chmod 755 -R /media

echo "$HOST_NAME" > /etc/hostname
ln -sf "/usr/share/zoneinfo/$TIME_ZONE" /etc/localtime
hwclock --systohc --utc
timedatectl set-ntp true

echo -e "en_US.UTF-8 UTF-8\nru_RU.UTF-8 UTF-8" > /etc/locale.gen
locale-gen
echo -e "LANG=ru_RU.UTF-8" > /etc/locale.conf
echo -e "KEYMAP=ru\nFONT=cyr-sun16" > /etc/vconsole.conf

pacman -S --noconfirm --needed haveged
haveged -w 1024
pacman-key --init && pacman-key --populate
pkill haveged

sed -i -e '/Color/s/^#//' -e '/VerbosePkgLists/s/^#//' -e '/\[multilib\]/,/Include/s/^#//' /etc/pacman.conf
pacman -Syy --noconfirm

echo "root:$PASSWORD" | chpasswd
useradd -m -g users -G "audio,video,input,adm,disk,log,network,scanner,storage,power,wheel" -s /usr/bin/zsh "$NEW_USER"
echo "$NEW_USER:$PASSWORD" | chpasswd
echo "%wheel ALL=(ALL) ALL" >> /etc/sudoers

chown -R "$NEW_USER":users /media/*


# === MKINITCPIO ===
# if [[ "$FS_TYPE" == "btrfs" ]]; then
#   sed -i 's/filesystems fsck/filesystems/' /etc/mkinitcpio.conf
# fi


# === VIRTUALIZATION ===
VIRT=\$(systemd-detect-virt)
if [[ "\$VIRT" == "oracle" || "\$VIRT" == "vbox" || "\$VIRT" == "container-other" ]]; then
  pacman -S --noconfirm --needed virtualbox-guest-utils
  systemctl enable vboxservice
  usermod -a -G vboxsf "$NEW_USER"
fi


# === HOSTS & NETWORK ===
cat <<EOF >/etc/hosts
127.0.0.1       localhost
::1             localhost
127.0.1.1       $HOST_NAME.localdomain $HOST_NAME
EOF

mkdir -p /etc/systemd/network
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


# === MAKEPKG OPTIMIZATION ===
sed -i -e "s/#MAKEFLAGS=.*/MAKEFLAGS=\"-j$THREADS\"/" \
       -e "s/COMPRESSZST=.*/COMPRESSZST=(zstd -c -T0 - --threads=0)/" \
       -e 's/\([^!]\)debug\b/\1!debug/' /etc/makepkg.conf


# === AUR HELPER (yay) ===
cd /home/$NEW_USER
sudo -u "$NEW_USER" git clone https://aur.archlinux.org/yay-bin.git
cd yay-bin
sudo -u "$NEW_USER" makepkg -sr --noconfirm
pacman -U --noconfirm --needed \$(ls *.pkg.tar.zst | grep -v "debug")
cd ~ && rm -rf /home/$NEW_USER/yay-bin


# === ZSH CONFIG ===
cat <<'ZSHRC' >/home/$NEW_USER/.zshrc
#!/usr/bin/zsh

# [[ -z \$DISPLAY && \$XDG_VTNR -eq 1 ]] && exec startx &> /dev/null

export PATH=\$HOME/.bin:\$HOME/.local/bin:\$PATH
export HISTFILE=~/.zhistory HISTSIZE=3000 SAVEHIST=3000
autoload -Uz compinit; for dump in ~/.zcompdump(N.mh+24); do compinit; done; compinit -C

[[ -e /usr/share/zsh/plugins/fast-syntax-highlighting/fast-syntax-highlighting.plugin.zsh ]] && source /usr/share/zsh/plugins/fast-syntax-highlighting/fast-syntax-highlighting.plugin.zsh

[[ -e /usr/share/zsh/plugins/zsh-autosuggestions/zsh-autosuggestions.zsh ]] && source /usr/share/zsh/plugins/zsh-autosuggestions/zsh-autosuggestions.zsh

if [[ -d /usr/share/oh-my-zsh ]]; then
  export ZSH="/usr/share/oh-my-zsh"
  ZSH_THEME="af-magic"
  DISABLE_AUTO_UPDATE="true"
  plugins=()
  ZSH_CACHE_DIR=\$HOME/.cache/oh-my-zsh
  mkdir -p \$ZSH_CACHE_DIR
  [[ -e \$ZSH/oh-my-zsh.sh ]] && source \$ZSH/oh-my-zsh.sh
else
  eval "\$(starship init zsh)"
fi
ZSHRC
chown -R "$NEW_USER":users /home/$NEW_USER


# === KERNEL MODULES & BLACKLIST ===
cat <<EOF >/etc/modprobe.d/blacklist.conf
blacklist iTCO_wdt
blacklist iTCO_vendor_support
blacklist sp5100_tco
EOF

cat <<EOF >/etc/modprobe.d/nvidia.conf
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

cat <<EOF >/etc/modules-load.d/gaming-performance.conf
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


# === ZRAM ===
cat <<EOF >/etc/systemd/zram-generator.conf
[zram0]
zram-size = 16384
compression-algorithm = lz4px
swap-priority = 100
fs-type = swap
EOF


# === SYSCTL ===
cat <<EOF >/etc/sysctl.d/99-gaming.conf
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
# (64 МБ): Как только в памяти накопится всего 64 МБ данных для записи, система начнет потихоньку сбрасывать их на NVMe
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


# === UDEV RULES ===
mkdir -p /etc/udev/rules.d
cat <<EOF >/etc/udev/rules.d/80-nvidia-pm.rules
# Запрещаем видеокарте уходить в глубокий сон (D3)
# Это критично для стабильного FPS и отсутствия лагов при выходе из сна
ACTION=="add", SUBSYSTEM=="pci", ATTR{vendor}=="0x10de", ATTR{class}=="0x030000", ATTR{power/control}="on"
EOF

cat <<EOF >/etc/udev/rules.d/60-ioschedulers.rules
# HDD (Вращающиеся диски)
# Запрещаем парковку головок и сон через hdparm
ACTION=="add|change", SUBSYSTEM=="block", KERNEL=="sd[a-z]*", ATTR{queue/rotational}=="1", RUN+="/usr/bin/hdparm -B 254 -S 0 /dev/%k"
# Планировщик BFQ лучше всего справляется с задержками механики
ACTION=="add|change", SUBSYSTEM=="block", KERNEL=="sd[a-z]*", ATTR{queue/rotational}=="1", ATTR{queue/scheduler}="bfq"

# SSD (SATA)
# Kyber отлично подходит для SATA SSD, уменьшая "затыки" при высокой нагрузке
ACTION=="add|change", SUBSYSTEM=="block", KERNEL=="sd[a-z]*|mmcblk[0-9]*", ATTR{queue/rotational}=="0", ATTR{queue/scheduler}="kyber"

# 5. NVMe (Твой Samsung 9100 PRO)
# Убираем все лишнее. NVMe сам знает, как распределять потоки.
ACTION=="add|change", SUBSYSTEM=="block", KERNEL=="nvme[0-9]n[0-9]*", ATTR{queue/rotational}=="0", ATTR{queue/scheduler}="none", ATTR{queue/rq_affinity}="2"
EOF

cat <<EOF >/etc/udev/rules.d/40-timer-permissions.rules
# для оптимизации прерываний реального времени
KERNEL=="rtc0", GROUP="audio"
KERNEL=="hpet", GROUP="audio"
EOF
udevadm control --reload-rules


# === NETWORKMANAGER ===
mkdir -p /etc/NetworkManager/conf.d
cat <<EOF >/etc/NetworkManager/conf.d/99-gaming.conf
[device]
# Отключаем случайную генерацию MAC-адресов (ускоряет подключение к роутеру)
wifi.scan-rand-mac-address=no
wifi.backend=iwd

[connection]
# Отключаем IPv6, если твой провайдер его не использует (убирает лишние запросы)
ipv6.method=ignore
# Настройка для Wi-Fi (если используешь чип MediaTek/Realtek на X870E)

[wifi]
# Отключаем агрессивное сканирование сетей в фоновом режиме.
# Это убирает резкие скачки пинга (lag spikes) каждые пару минут.
powersave=2
EOF


# === PIPEWIRE ===
mkdir -p /etc/pipewire/pipewire.conf.d
cat <<EOF >/etc/pipewire/pipewire.conf.d/99-low-latency.conf
context.properties = {
    default.clock.rate = 48000
    default.clock.allowed-rates = [ 44100 48000 88200 96000 ]
    default.clock.quantum = 128
    default.clock.min-quantum = 64
    default.clock.max-quantum = 1024
}
EOF


# === LIMITS ===
mkdir -p /etc/security/limits.d
cat <<EOF >/etc/security/limits.d/99-gaming.conf
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


# === LOGS SYSTEMD ===
mkdir -p /etc/systemd/journald.conf.d
cat <<EOF >/etc/systemd/journald.conf.d/90-storage.conf
[Journal]
Storage=auto
RuntimeMaxUse=50M
SystemMaxUse=100M
SyncIntervalSec=5m
EOF


# === TIMEOUT WATCHDOG ===
# ускорение перезагрузки
mkdir -p /etc/systemd/system.conf.d
cat <<EOF >/etc/systemd/system.conf.d/90-timeout.conf
[Manager]
DefaultTimeoutStartSec=15s
DefaultTimeoutStopSec=10s
EOF


# === BOOTLOADER ===
log "Final initramfs rebuild..."
mkinitcpio -P

if [[ "$BOOT_LOADER" == "grub-efi" ]]; then
  grub-install --target=x86_64-efi --efi-directory=/boot/efi --bootloader-id=GRUB
  sed -i "s|^GRUB_CMDLINE_LINUX_DEFAULT=.*|GRUB_CMDLINE_LINUX_DEFAULT=\"$KERNEL_PARAMS\"|" /etc/default/grub
  sed -i '/#GRUB_DISABLE_OS_PROBER/s/^#//' /etc/default/grub
  grub-mkconfig -o /boot/grub/grub.cfg
elif [[ "$BOOT_LOADER" == "grub" ]]; then
  grub-install "$DISK"
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
title Rach Linups (zen)
linux /vmlinuz-linux-zen
initrd /amd-ucode.img
initrd /initramfs-linux-zen.img
# options root=UUID=$ROOT_UUID $SYSTEMD_FLAGS rw loglevel=3 nowatchdog nmi_watchdog=0
options root=UUID=$ROOT_UUID $SYSTEMD_FLAGS rw $KERNEL_PARAMS
EOF
  cat <<EOF >/boot/loader/entries/arch.conf
title Rach Linups (Arch Kernel)
linux /vmlinuz-linux
initrd /amd-ucode.img
initrd /initramfs-linux.img
options root=UUID=$ROOT_UUID $SYSTEMD_FLAGS rw
EOF
fi

# === GAME-RUN SCRIPT ===
cat <<'GAME_RUN' >/usr/local/bin/game-run
#!/bin/bash
powerprofilesctl set performance
## Настройки NVIDIA & Sync (Для G-Sync и 240Hz)
export __GL_GSYNC_ALLOWED=1
export __GL_VRR_ALLOWED=1
export __GL_MAX_FRAMES_ALLOWED=1
export __GL_YIELD="NOTHING"
## Настройки PRIME (Форсируем дискретную карту)
export __NV_PRIME_RENDER_OFFLOAD=1
export __GLX_VENDOR_LIBRARY_NAME=nvidia
export __VK_LAYER_NV_optimus=NVIDIA_only
## Proton & Ray Tracing (NVAPI для DLSS и лучей)
export PROTON_ENABLE_NVAPI=1
export PROTON_HIDE_NVIDIA_GPU=0
export VKD3D_CONFIG=dxr11,force_compute_root_parameters_push_constants

nice -n -10 taskset -c 0-7,16-23 gamemoderun gamescope -r 240 -f -e -- mangohud "\$@"

# или под монитор с частотой и разрешением
# nice -n -10 taskset -c 0-7,16-23 gamemoderun gamescope -W 3440 -H 1440 -r 240 -f -e -- mangohud "\$@"

powerprofilesctl set balanced
GAME_RUN
chmod +x /usr/local/bin/game-run


# === SERVICES ===
systemctl enable sshd
systemctl enable NetworkManager
# systemctl enable sddm
systemctl enable plasmalogin
systemctl enable power-profiles-daemon
systemctl enable ananicy-cpp
if pacman -Qs ananicy-cpp > /dev/null; then
systemctl enable ananicy-cpp
fi
# systemctl enable bluetooth
# systemctl enable avahi-daemon
## To have GRUB automatically detect Timeshift/Snapper snapshots
if pacman -Qs grub-btrfs > /dev/null; then
systemctl enable grub-btrfsd
fi
log "Post-install complete"
CHROOT_SCRIPT

chmod +x /mnt/post-install.sh
arch-chroot /mnt /bin/bash -c "/post-install.sh"
rm /mnt/post-install.sh

# === FINALIZE ===
log "Installation complete!"
if read -re -p "Enter chroot for manual tweaks? [y/N]: " ans && [[ $ans =~ ^[Yy]$ ]]; then
  arch-chroot /mnt
else
  umount -lR /mnt
fi
# wipefs -a /dev/sda

cat <<EOF

>>> Next steps:

>>> Check logs: cat /tmp/install.log
>>> Umount mnt: sudo umount -Rl /mnt
>>> Reboot: sudo systemctl reboot

>>> yay -S --noconfirm oh-my-zsh-git zsh-fast-syntax-highlighting cachyos-ananicy-rules-git vkbasalt lib32-vkbasalt proton-ge-custom-bin protonup-qt-bin dxvk-bin heroic-games-launcher-bin
EOF