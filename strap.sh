#!/bin/sh

# fork blackarch strap.sh

MIRROR_F="ctlos-mirrorlist"

err()
{
  echo >&2 "$(tput bold; tput setaf 1)[-] ERROR: ${*}$(tput sgr0)"

  exit 1337
}
warn()
{
  echo >&2 "$(tput bold; tput setaf 1)[!] WARNING: ${*}$(tput sgr0)"
}
msg()
{
  echo "$(tput bold; tput setaf 2)[+] ${*}$(tput sgr0)"
}
check_priv()
{
  if [ "$(id -u)" -ne 0 ]; then
    err "you must be root"
  fi
}

make_tmp_dir()
{
  tmp="$(mktemp -d /tmp/ctlos_strap.XXXXXXXX)"

  trap 'rm -rf $tmp' EXIT

  cd "$tmp" || err "Could not enter directory $tmp"
}

check_internet()
{
  tool='curl'
  tool_opts='-s --connect-timeout 8'

  if ! $tool $tool_opts https://google.com/ > /dev/null 2>&1; then
    err "You don't have an Internet connection!"
  fi

  return $SUCCESS
}

# retrieve the Ctlos Linux keyring
fetch_keyring()
{
  wget https://github.com/ctlos/ctlos_repo/raw/dev/x86_64/ctlos-keyring-20200714-4-any.pkg.tar.zst{,.sig}
}

# verify the keyring signature
verify_keyring()
{
  if [ -f "/usr/share/pacman/keyrings/ctlos.gpg" ]; then
    wget -P /usr/share/pacman/keyrings git.io/ctlos.gpg
    pacman-key --add /usr/share/pacman/keyrings/ctlos.gpg
    # pacman-key --recv-keys 98F76D97B786E6A3
    pacman-key --lsign-key 98F76D97B786E6A3
  fi
}

# delete the signature files
delete_signature()
{
  if [ -f "ctlos-keyring-20200714-4-any.pkg.tar.zst.sig" ]; then
    rm ctlos-keyring-20200714-4-any.pkg.tar.zst.sig
  fi
}

# make sure /etc/pacman.d/gnupg is usable
check_pacman_gnupg()
{
  pacman-key --init
}

# install the keyring
install_keyring()
{
  if ! pacman --config /dev/null --noconfirm \
    -U ctlos-keyring-20200714-4-any.pkg.tar.zst ; then
    err 'keyring installation failed'
  fi

  # just in case
  pacman-key --populate
}

install_mirrors()
{
  wget https://github.com/ctlos/ctlos_repo/raw/dev/x86_64/ctlos-mirrorlist-20200714-2-any.pkg.tar.zst{,.sig}

  if [ -f "ctlos-mirrorlist-20200714-2-any.pkg.tar.zst.sig" ]; then
    rm ctlos-mirrorlist-20200714-2-any.pkg.tar.zst.sig
  fi

  if ! pacman --config /dev/null --noconfirm \
    -U ctlos-mirrorlist-20200714-2-any.pkg.tar.zst ; then
    err 'mirrors installation failed'
  fi
}

# update pacman.conf
update_pacman_conf()
{
  # delete ctlos related entries if existing
  sed -i '/ctlos_repo/{N;d}' /etc/pacman.conf

  cat >> "/etc/pacman.conf" << EOF
[ctlos_repo]
Include = /etc/pacman.d/$MIRROR_F
EOF
}

# synchronize and update
pacman_update()
{
  if pacman -Syy; then
    return $SUCCESS
  fi

  warn "Synchronizing pacman has failed. Please try manually: pacman -Syy"

  return $FAILURE
}


pacman_upgrade()
{
  echo 'perform full system upgrade? (pacman -Su) [Yn]:'
  read conf < /dev/tty
  case "$conf" in
    ''|y|Y) pacman -Su ;;
    n|N) warn 'some ctlos packages may not work without an up-to-date system.' ;;
  esac
}

# setup ctlos linux
ctlos_setup()
{
  check_priv
  msg 'installing ctlos keyring...'
  make_tmp_dir
  check_internet
  fetch_keyring
  verify_keyring
  delete_signature
  check_pacman_gnupg
  install_keyring
  echo
  msg 'keyring installed successfully'
  install_mirrors
  echo
  msg 'mirrorlist installed successfully'
  # check if pacman.conf has already a mirror
  if ! grep -q "\[ctlos_repo\]" /etc/pacman.conf; then
    msg 'configuring pacman'
    msg 'updating pacman.conf'
    update_pacman_conf
  fi
  msg 'updating package databases'
  pacman_update
  # pacman_upgrade
  msg 'Ctlos Linux is ready!'
}

ctlos_setup
