#!/bin/sh

# Based on https://muxup.com/2026q2/bootable-qemu-image-menagerie-with-rootless-debootstrap

TGT=riscv64-trixie-for-qemu

# Uses <https://github.com/muxup/medley/blob/main/rootless-debootstrap-wrapper>
~/rootless-debootstrap-wrapper \
  --arch=riscv64 \
  --suite=trixie \
  --mirror=https://deb.debian.org/debian \
  --cache-dir="$HOME/debcache" \
  --target-dir=$TGT \
  --include=linux-image-riscv64,zstd,dbus,systemd-resolved,systemd-timesyncd,openssh-server,sudo,python3,python3-psutil,git,libxml2 || exit 1

"$TGT/_enter" sh -e <<'EOF' || exit 1
mkdir -p \
  /etc/systemd/network \
  /etc/ssh/sshd_config.d \
  /etc/systemd/system/ssh.service.d \
  /etc/systemd/system/sshd-vsock@.service.d

cat - <<'INNER_EOF' > /etc/systemd/network/10-qemu.network
[Match]
Type=ether

[Network]
DHCP=yes
INNER_EOF

cat - <<'INNER_EOF' > /etc/ssh/sshd_config.d/20-qemu-login.conf
PermitRootLogin yes
PasswordAuthentication yes
INNER_EOF

rm -f /etc/ssh/ssh_host_*_key /etc/ssh/ssh_host_*_key.pub

cat - <<'INNER_EOF' > /etc/systemd/system/ssh.service.d/10-ephemeral-authorized-keys.conf
[Service]
ImportCredential=ssh.authorized_keys
ExecStart=
ExecStart=/usr/sbin/sshd -D $SSHD_OPTS -o "AuthorizedKeysFile .ssh/authorized_keys" -o "AuthorizedKeysCommand /usr/bin/cat ${CREDENTIALS_DIRECTORY}/ssh.authorized_keys" -o "AuthorizedKeysCommandUser root"
INNER_EOF

cat - <<'INNER_EOF' > /etc/systemd/system/sshd-vsock@.service.d/10-ephemeral-authorized-keys.conf
[Service]
ImportCredential=ssh.authorized_keys
ExecStart=
ExecStart=-/usr/sbin/sshd -i $SSHD_OPTS -o "AuthorizedKeysFile .ssh/authorized_keys" -o "AuthorizedKeysCommand /usr/bin/cat ${CREDENTIALS_DIRECTORY}/ssh.authorized_keys" -o "AuthorizedKeysCommandUser root"
INNER_EOF

/usr/bin/systemd-firstboot --locale=C.UTF-8 --hostname=qemu-riscv64-trixie --force
ln -sf ../locale.conf /etc/default/locale
printf '127.0.1.1 qemu-riscv64-trixie\n' >> /etc/hosts
printf 'uninitialized\n' > /etc/machine-id
mkdir -p /var/lib/dbus
rm -f /var/lib/dbus/machine-id
ln -sf /etc/machine-id /var/lib/dbus/machine-id

systemctl enable systemd-networkd systemd-resolved systemd-timesyncd ssh
systemctl enable serial-getty@ttyS0.service
ln -sf ../run/systemd/resolve/resolv.conf /etc/resolv.conf
echo root:root | chpasswd
adduser --gecos ",,," --disabled-password user
usermod -aG sudo user
echo user:user | chpasswd

echo "Finished rootfs config"
EOF

fakeroot -i $TGT/.fakeroot.env sh -e <<EOF || exit 1
cp $TGT/boot/vmlinux-* kernel
cp $TGT/boot/initrd.img-* initrd
mkfs.ext4 -q -L rootfs -d $TGT rootfs.img 30G
EOF

tar --sparse --zstd -cf riscv64-debian-trixie-appliance.tar.zst rootfs.img kernel initrd
