#!/bin/sh
# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.

if [ "$1" = "--step-chroot" ]; then
	echo -n "  Installing packages..." >&2
	apk update >/dev/null 2>&1
	apk add alpine-base linux-virthardened syslinux grub grub-bios e2fsprogs >/dev/null 2>/dev/null
	echo " Done" >&2

	echo -n "  Configuring network and services..." >&2
	IP_ADDR=$(wget -q -O- http://169.254.169.254/metadata/v1/interfaces/public/0/ipv4/address)
	IP_NETMASK=$(wget -q -O- http://169.254.169.254/metadata/v1/interfaces/public/0/ipv4/netmask)
	IP_GATEWAY=$(wget -q -O- http://169.254.169.254/metadata/v1/interfaces/public/0/ipv4/gateway)

	cat <<EOF > /etc/network/interfaces
auto lo
iface lo inet loopback

auto eth0
iface eth0 inet static
    address $IP_ADDR
    netmask $IP_NETMASK
    gateway $IP_GATEWAY
EOF

	IP_ADDR=$(wget -q -O- http://169.254.169.254/metadata/v1/interfaces/public/0/ipv6/address 2>/dev/null)
	HAS_IPv6=$?
	IP_CIDR=$(wget -q -O- http://169.254.169.254/metadata/v1/interfaces/public/0/ipv6/cidr 2>/dev/null)
	IP_GATEWAY=$(wget -q -O- http://169.254.169.254/metadata/v1/interfaces/public/0/ipv6/gateway 2>/dev/null)

	if [ "$HAS_IPv6" -eq 0 ]; then
		echo "ipv6" >> /etc/modules
		cat <<EOF >> /etc/network/interfaces

iface eth0 inet6 static
    address $ID_ADDR
    netmask $IP_CIDR
    gateway $IP_GATEWAY
    pre-up echo 0 > /proc/sys/net/ipv6/conf/eth0/accept_ra
EOF
	fi

	IP_ADDR=$(wget -q -O- http://169.254.169.254/metadata/v1/interfaces/private/0/ipv4/address 2>/dev/null)
	HAS_PRIVATE=$?
	IP_NETMASK=$(wget -q -O- http://169.254.169.254/metadata/v1/interfaces/private/0/ipv4/netmask 2>/dev/null)

	if [ "$HAS_PRIVATE" -eq 0 ]; then
		cat <<EOF >> /etc/network/interfaces

auto eth1
iface eth1 inet static
    address $IP_ADDR
    netmask $IP_NETMASK
EOF
	fi

	setup-sshd -c openssh >/dev/null 2>&1

	rc-update add --quiet hostname boot
	rc-update add --quiet networking boot
	rc-update add --quiet urandom boot
	rc-update add --quiet crond
	rc-update add --quiet swap boot

	sed -i -r -e 's/^UsePAM yes$/#\1/' /etc/ssh/sshd_config

	sed -i -r -e 's/^(tty[2-6]:)/#\1/' /etc/inittab

	echo " Done" >&2

	echo -n "  Installing bootloader..." >&2

	grub-install /dev/vda >/dev/null 2>&1
	grub-mkconfig -o /boot/grub/grub.cfg >/dev/null 2>&1

	sync
	echo " Done" >&2

	rm -f "$0"

	exit
fi

if [ "$1" != "--rebuild" ]; then
	echo "usage: digitalocean-alpine --rebuild" >&2
	echo "   Rebuild the current droplet with Alpine Linux" >&2
	echo >&2
	echo "   WARNING: This is a destructive operation. You will lose your data." >&2
	echo "            This script has only been tested with Debian 9.3 x64 droplets." >&2
	exit 1
fi

if [ "$(id -u)" -ne "0" ]; then
	echo "digitalocean-alpine: script must be run as root" >&2
	exit 1
fi

SCRIPTPATH="$(realpath "$0")"

if [ \! -x "$SCRIPTPATH" ]; then
	echo "digitalocean-alpine: script must be executable" >&2
	exit 1
fi

echo -n "Downloading Alpine 3.7.0..." >&2
wget -q -O /tmp/rootfs.tar.gz http://dl-cdn.alpinelinux.org/alpine/v3.7/releases/x86_64/alpine-minirootfs-3.7.0-x86_64.tar.gz
if [ "$?" -ne 0 ]; then
	echo "Could not download Alpine. Exiting." >&2
	exit 1
fi
echo " Done" >&2

echo -n "Creating mount points..." >&2
umount -a >/dev/null 2>&1
mount -o rw,remount --make-rprivate /dev/vda1 /
mkdir /tmp/tmpalpine
mount none /tmp/tmpalpine -t tmpfs
echo " Done" >&2

echo -n "Extracting Alpine..." >&2
tar xzf /tmp/rootfs.tar.gz -C /tmp/tmpalpine
cp "$SCRIPTPATH" /tmp/tmpalpine/tmp/digitalocean-alpine.sh
echo " Done" >&2

echo -n "Copying existing droplet configuration..." >&2
cp /etc/fstab /tmp/tmpalpine/etc
cp /etc/hostname /tmp/tmpalpine/etc
cp /etc/resolv.conf /tmp/tmpalpine/etc
grep -v ^root: /tmp/tmpalpine/etc/shadow > /tmp/tmpalpine/etc/shadow.bak
mv /tmp/tmpalpine/etc/shadow.bak /tmp/tmpalpine/etc/shadow
grep ^root: /etc/shadow >> /tmp/tmpalpine/etc/shadow
cp -r /etc/ssh /tmp/tmpalpine/etc
cp -r /root/.ssh /tmp/tmpalpine/root
echo " Done" >&2

echo -n "Changing to new root..." >&2
mkdir /tmp/tmpalpine/oldroot
pivot_root /tmp/tmpalpine /tmp/tmpalpine/oldroot
cd /
echo " Done" >&2

echo -n "Rebuilding file systems..." >&2
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
chroot /oldroot /bin/ash /tmp/digitalocean-alpine.sh --step-chroot

echo "Rebooting system. You should be able to reconnect shortly."  >&2
reboot
sleep 1
reboot
