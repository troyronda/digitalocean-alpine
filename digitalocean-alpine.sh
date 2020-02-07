#!/bin/sh
# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.

logfile="/tmp/digitalocean-alpine.log"

if [ "$1" = "--step-chroot" ]; then
	printf "" > "$logfile"

	printf "  Installing packages..." >&2

	cat <<EOF > /etc/apk/keys/troyronda.com-5e2d9b70.rsa.pub
-----BEGIN PUBLIC KEY-----
MIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEAvb0Jk9qn6+8Wa/GGmtv+
glwbOsX5+1FW1m8jl5ZgG26qxir+WobM6PNTGUGxpo+j9tHCFDHXCFT4XcrJJRMc
U8TPtMqKwxN4u99ziyJ+nGehIEbFpLRzTCHXhayv6I3du5yEU4dCtWGFsVspoU6d
Y4qDprKyLZnBKEx8NivI5w93s4OCQGUy+re7V2Ftxp6HEUCDpLhKu9ebnl7u+Dy6
mAhNk0kGBfa3sVf+cpWn1Zmk2mGH5JQ17hmB4PJAXWGFWjjIXcpC29OZRA6Cuac8
1FxGfW+U00asAgbaZ1KQGTNsLgErmCUjqYL9Ct1zsP0xkE9Hr8vvJH98I1PREWhj
zwIDAQAB
-----END PUBLIC KEY-----
EOF
	echo "https://cdn.layeh.com/alpine/3.10/" >> /etc/apk/repositories

	if ! apk add --no-cache alpine-base linux-virt syslinux grub grub-bios e2fsprogs eudev openssh rng-tools rng-tools-openrc digitalocean-alpine >>"$logfile" 2>>"$logfile"; then
		echo
		exit 1
	fi

	echo " Done" >&2

	printf "  Configuring services..." >&2

	rc-update add --quiet hostname boot
	rc-update add --quiet networking boot
	rc-update add --quiet urandom boot
	rc-update add --quiet crond default
	rc-update add --quiet swap boot
	rc-update add --quiet udev sysinit
	rc-update add --quiet udev-trigger sysinit
	rc-update add --quiet sshd default
	rc-update add --quiet digitalocean boot
	rc-update add --quiet rngd boot

	sed -i -r -e 's/^(tty[2-6]:)/#\1/' /etc/inittab

	echo "/dev/vdb	/media/cdrom	iso9660	ro	0	0" >> /etc/fstab

	echo " Done" >&2

	printf "  Installing bootloader..." >&2

	if ! grub-install /dev/vda >>"$logfile" 2>>"$logfile"; then
		echo
		exit 1
	fi
	if ! grub-mkconfig -o /boot/grub/grub.cfg >>"$logfile" 2>>"$logfile"; then
		echo
		exit 1
	fi

	sync
	echo " Done" >&2

	rm -f "$0"

	exit 0
fi

if [ "$1" != "--rebuild" ]; then
	echo "usage: digitalocean-alpine --rebuild" >&2
	echo "   Rebuild the current droplet with Alpine Linux" >&2
	echo >&2
	echo "   WARNING: This is a destructive operation. You will lose your data." >&2
	echo "            This script has only been tested with debian-10 x64 droplets." >&2
	exit 1
fi

if [ -f /etc/alpine-release ]; then
	echo "digitalocean-alpine: Alpine Linux already installed" >&2
	exit 0
fi

if [ "$(id -u)" -ne "0" ]; then
	echo "digitalocean-alpine: script must be run as root" >&2
	exit 1
fi

SCRIPTPATH="$(realpath "$0")"

if [ ! -x "$SCRIPTPATH" ]; then
	echo "digitalocean-alpine: script must be executable" >&2
	exit 1
fi

printf "Downloading Alpine 3.11.3..." >&2
if ! wget -q -O /tmp/rootfs.tar.gz http://dl-cdn.alpinelinux.org/alpine/v3.11/releases/x86_64/alpine-minirootfs-3.11.3-x86_64.tar.gz; then
	echo " Failed!" >&2
	exit 1
fi
echo " Done" >&2

printf "Verifying SHA256 checksum..." >&2
if ! echo "8a6c827f137058ac3e3df1125891ff5c3b62955f0b911adec26eae6ea2bbb285  /tmp/rootfs.tar.gz" | sha256sum -c >/dev/null 2>&1; then
	echo " Failed!" >&2
	exit 1
fi
echo " Done" >&2

printf "Creating mount points..." >&2
umount -a >/dev/null 2>&1
mount -o rw,remount --make-rprivate /dev/vda1 /
mkdir /tmp/tmpalpine
mount none /tmp/tmpalpine -t tmpfs
echo " Done" >&2

printf "Extracting Alpine..." >&2
tar xzf /tmp/rootfs.tar.gz -C /tmp/tmpalpine
cp "$SCRIPTPATH" /tmp/tmpalpine/tmp/digitalocean-alpine.sh
echo " Done" >&2

printf "Copying existing droplet configuration..." >&2
cp /etc/fstab /tmp/tmpalpine/etc
cp /etc/hostname /tmp/tmpalpine/etc
cp /etc/resolv.conf /tmp/tmpalpine/etc
grep -v ^root: /tmp/tmpalpine/etc/shadow > /tmp/tmpalpine/etc/shadow.bak
mv /tmp/tmpalpine/etc/shadow.bak /tmp/tmpalpine/etc/shadow
grep ^root: /etc/shadow >> /tmp/tmpalpine/etc/shadow
mkdir -p /tmp/tmpalpine/etc/ssh
cp -r /etc/ssh/ssh_host_* /tmp/tmpalpine/etc/ssh
cp -r /root/.ssh /tmp/tmpalpine/root
echo " Done" >&2

printf "Changing to new root..." >&2
mkdir /tmp/tmpalpine/oldroot
pivot_root /tmp/tmpalpine /tmp/tmpalpine/oldroot
cd / || exit 1
echo " Done" >&2

printf "Rebuilding file systems..." >&2
mount --move /oldroot/dev /dev
mount --move /oldroot/proc /proc
mount --move /oldroot/sys /sys
mount --move /oldroot/run /run

rm -rf /oldroot/*

cp -r /bin /etc /home /lib/ /media /mnt/ /root /sbin /srv /tmp /usr /var /oldroot

mkdir /oldroot/dev /oldroot/proc /oldroot/sys /oldroot/run

mount -t proc proc /oldroot/proc
mount -t sysfs sys /oldroot/sys
mount -o bind /dev /oldroot/dev

echo " Done" >&2

echo "chroot configuration..." >&2
if ! chroot /oldroot /bin/ash /tmp/digitalocean-alpine.sh --step-chroot; then
	echo "ERROR: could not install Alpine Linux. See /oldroot$logfile" >&2
	exit 1
fi

echo "Rebooting system. You should be able to reconnect shortly." >&2
reboot
sleep 1
reboot
