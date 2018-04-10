#!/bin/sh
# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.

if [ "$1" = "--step-chroot" ]; then

	echo -n "  Adding Digital Ocean init script..." >&2
	cat <<EOF > /etc/init.d/digitalocean
#!/sbin/openrc-run

description="Loads Digital Ocean droplet configuration"

required_files="/media/cdrom/digitalocean_meta_data.json"

depend() {
	need localmount
	before network
	before hostname
}

start() {
	ebegin "Loading Digital Ocean configuration"
	if ! which jq >/dev/null 2>&1; then
		eend 1 "jq is not installed"
	fi

	hostname="\$(jq -jre '.hostname' /media/cdrom/digitalocean_meta_data.json 2>/dev/null)"
	if [ \$? -eq 0 ]; then
		echo "\$hostname" > /etc/hostname
	else
		ewarn "Could not read hostname"
	fi

	f="/etc/network/interfaces"

	echo "auto lo" > "\$f"
	echo "iface lo inet loopback" >> "\$f"

	ip_addr="\$(jq -jre '.interfaces.public[0].ipv4.ip_address' /media/cdrom/digitalocean_meta_data.json 2>/dev/null)"
	ip_netmask="\$(jq -jre '.interfaces.public[0].ipv4.netmask' /media/cdrom/digitalocean_meta_data.json 2>/dev/null)"
	ip_gateway="\$(jq -jre '.interfaces.public[0].ipv4.gateway' /media/cdrom/digitalocean_meta_data.json 2>/dev/null)"

	echo >> "\$f"
	echo "auto eth0" >> "\$f"
	echo "iface eth0 inet static" >> "\$f"
	echo "	address \$ip_addr" >> "\$f"
	echo "	netmask \$ip_netmask" >> "\$f"
	echo "	gateway \$ip_gateway" >> "\$f"

	ip_addr="\$(jq -jre '.interfaces.public[0].ipv6.ip_address' /media/cdrom/digitalocean_meta_data.json 2>/dev/null)"
	ip_cidr="\$(jq -jre '.interfaces.public[0].ipv6.cidr' /media/cdrom/digitalocean_meta_data.json 2>/dev/null)"
	ip_gateway="\$(jq -jre '.interfaces.public[0].ipv6.gateway' /media/cdrom/digitalocean_meta_data.json 2>/dev/null)"

	if [ -n "\$ip_addr" ]; then
		modprobe ipv6

		echo >> "\$f"
		echo "iface eth0 inet6 static" >> "\$f"
		echo "	address \$ip_addr" >> "\$f"
		echo "	netmask \$ip_cidr" >> "\$f"
		echo "	gateway \$ip_gateway" >> "\$f"
		echo "	pre-up echo 0 > /proc/sys/net/ipv6/conf/eth0/accept_ra" >> "\$f"
	fi

	ip_addr="\$(jq -jre '.interfaces.private[0].ipv4.ip_address' /media/cdrom/digitalocean_meta_data.json 2>/dev/null)"
	ip_netmask="\$(jq -jre '.interfaces.private[0].ipv4.netmask' /media/cdrom/digitalocean_meta_data.json 2>/dev/null)"

	if [ -n "\$ip_addr" ]; then
		echo >> "\$f"
		echo "auto eth1" >> "\$f"
		echo "iface eth1 inet static" >> "\$f"
		echo "	address \$ip_addr" >> "\$f"
		echo "	netmask \$ip_netmask" >> "\$f"
	fi

	eend 0
}
EOF
	chmod +x /etc/init.d/digitalocean
	echo " Done" >&2

	echo -n "  Installing packages..." >&2
	apk update >/dev/null 2>&1
	apk add alpine-base linux-virthardened syslinux grub grub-bios e2fsprogs jq eudev >/dev/null 2>&1
	echo " Done" >&2

	echo -n "  Configuring services..." >&2
	setup-sshd -c openssh >/dev/null 2>&1

	rc-update add --quiet hostname boot
	rc-update add --quiet networking boot
	rc-update add --quiet urandom boot
	rc-update add --quiet crond default
	rc-update add --quiet swap boot
	rc-update add --quiet udev sysinit
	rc-update add --quiet udev-trigger sysinit
	rc-update add --quiet digitalocean boot

	sed -i -r -e 's/^UsePAM yes$/#\1/' /etc/ssh/sshd_config

	sed -i -r -e 's/^(tty[2-6]:)/#\1/' /etc/inittab

	echo "/dev/vdb	/media/cdrom	iso9660	ro	0	0" >> /etc/fstab

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
