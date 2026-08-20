#!/usr/bin/env bash
set -e

echo "install script executed"

pkg update -y
pkg install -y proot curl wget tar xz-utils

GENTOO_DIR="$HOME/gentoo-fs"
mkdir -p "$GENTOO_DIR"

ARCH=$(uname -m)
case "$ARCH" in
    aarch64) ARCH_URL="arm64" ;;
    armv7l|armv8l) ARCH_URL="armhf" ;;
    x86_64) ARCH_URL="amd64" ;;
    *) echo "[-] Unsupported arch: $ARCH"; exit 1 ;;
esac

BASE_URL="https://images.linuxcontainers.org/images/gentoo/current/${ARCH_URL}/openrc"

echo "[+] Finding latest Gentoo build"
LATEST_BUILD=$(curl -sL "$BASE_URL/" | grep -oE '20[0-9]{6}_[0-9]{2}:[0-9]{2}' | tail -n 1)

if [ -z "$LATEST_BUILD" ]; then
    echo "[-] Error: Couldn't parse latest build timestamp from LXC mirror."
    exit 1
fi

ROOTFS_URL="${BASE_URL}/${LATEST_BUILD}/rootfs.tar.xz"
TARBALL="$HOME/rootfs.tar.xz"

echo "[+] Found build: ${LATEST_BUILD}"

echo "[+] Downloading Gentoo"
wget --show-progress -O "$TARBALL" "$ROOTFS_URL"

echo "[+] Extracting rootfs into $GENTOO_DIR"
tar -xf "$TARBALL" -C "$GENTOO_DIR" --overwrite 2>/dev/null || true
rm -f "$TARBALL"

mkdir -p "$GENTOO_DIR/etc"
rm -rf "$GENTOO_DIR/etc/resolv.conf"
echo "nameserver 8.8.8.8" > "$GENTOO_DIR/etc/resolv.conf"
echo "nameserver 1.1.1.1" >> "$GENTOO_DIR/etc/resolv.conf"

mkdir -p "$GENTOO_DIR/root"
chmod -R 777 "$GENTOO_DIR/root" 2>/dev/null || true
rm -f "$GENTOO_DIR/root/first_boot.sh"

cat << 'EOF' > "$GENTOO_DIR/root/first_boot.sh"
#!/bin/sh
if [ ! -f /root/.initialized ]; then
    echo "Initializing Gentoo OpenRC environment."
    mkdir -p /run/openrc
    touch /run/openrc/softlevel
    touch /root/.initialized
fi
EOF

chmod +x "$GENTOO_DIR/root/first_boot.sh"

cat << 'EOF' > "$GENTOO_DIR/root/.bashrc"
# Auto-run first boot installer
if [ -f /root/first_boot.sh ]; then
    /root/first_boot.sh
    rm -f /root/first_boot.sh
fi

# Print login banner
echo ""
echo "=================================================="
echo " Gentoo Linux (OpenRC)"
echo " To emerge packages: emerge --ask <package>"
echo " To check OpenRC: rc-status"
echo " To exit: exit"
echo "=================================================="
echo ""
EOF

LAUNCHER="$HOME/gentoo.sh"

cat << 'EOF' > "$LAUNCHER"
#!/usr/bin/env bash
GENTOO_DIR="$HOME/gentoo-fs"

if [ ! -d "$GENTOO_DIR" ]; then
    echo "[-] Error: Gentoo filesystem not found at $GENTOO_DIR"
    exit 1
fi

echo "[+] Starting Gentoo"

# Execute PRoot session
#!/data/data/com.termux/files/usr/bin/bash
cd $(dirname $0)
## unset LD_PRELOAD in case termux-exec is installed
unset LD_PRELOAD
command="proot"
command+=" --link2symlink"
command+=" -i 0:3003"
command+=" -r gentoo-fs"
if [ -n "$(ls -A gentoo-binds 2>/dev/null)" ]; then
    for f in gentoo-binds/* ;do
        . $f
    done
fi
command+=" -b /dev"
command+=" -b /proc"
command+=" -b gentoo-fs/root:/dev/shm"
## uncomment the following line to have access to the home directory of termux
#command+=" -b /data/data/com.termux/files/home:/root"
## uncomment the following line to mount /sdcard directly to /
#command+=" -b /sdcard"
command+=" -w /root"
command+=" /usr/bin/env -i"
command+=" HOME=/root"
command+=" PATH=/bin:/usr/bin:/sbin:/usr/sbin"
command+=" TERM=$TERM"
command+=" LANG=en_US.UTF-8"
command+=" LC_ALL=C"
command+=" LANGUAGE=en_US"
command+=" /bin/bash --login"
com="$@"
if [ -z "$1" ];then
    exec $command
else
    $command -c "$com"
fi

echo "[+] Exited Gentoo."
EOF

chmod +x "$LAUNCHER"

echo ""
echo "=================================================="
echo "  Gentoo installed."
echo "  Start Gentoo using ./gentoo.sh"
echo "=================================================="
