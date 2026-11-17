#!/bin/bash
set -ex
export DEBIAN_FRONTEND=noninteractive
apt-get install -y -q grub-pc-bin grub-efi-amd64-bin mtools >/dev/null 2>&1 || true
W=/tmp/iso; R=$W/rootfs; rm -rf $W; mkdir -p $W/iso/casper $W/iso/boot/grub
debootstrap --variant=minbase --components=main,universe --include=systemd-sysv,dbus,udev,ca-certificates noble $R http://archive.ubuntu.com/ubuntu
cat > $R/etc/apt/sources.list <<S
deb http://archive.ubuntu.com/ubuntu noble main universe
deb http://archive.ubuntu.com/ubuntu noble-updates main universe
deb http://security.ubuntu.com/ubuntu noble-security main universe
S
echo exit 101 > $R/usr/sbin/policy-rc.d; chmod +x $R/usr/sbin/policy-rc.d
for m in proc sys dev dev/pts; do mount --bind /$m $R/$m; done
chroot $R apt-get update -q
chroot $R apt-get install -y -q --no-install-recommends linux-image-generic casper initramfs-tools xserver-xorg-core xserver-xorg-input-libinput xserver-xorg-video-vesa xserver-xorg-video-fbdev xserver-xorg-video-vmware xinit x11-xserver-utils xauth dbus-x11 surf matchbox-window-manager libgl1-mesa-dri fonts-dejavu-core fonts-noto-color-emoji xkb-data
mkdir -p $R/opt/marea $R/etc/X11/xorg.conf.d
cp /mnt/user-data/outputs/marea-os.html $R/opt/marea/index.html
cat > $R/etc/X11/xorg.conf.d/00-keyboard.conf <<S
Section "InputClass"
 Identifier "kb"
 MatchIsKeyboard "on"
 Option "XkbLayout" "latam"
EndSection
S
cat > $R/opt/marea/session.sh <<'S'
#!/bin/sh
export WEBKIT_DISABLE_COMPOSITING_MODE=1 WEBKIT_DISABLE_DMABUF_RENDERER=1 LIBGL_ALWAYS_SOFTWARE=1 WEBKIT_DISABLE_SANDBOX_THIS_IS_DANGEROUS=1 GDK_BACKEND=x11 HOME=/root
xset s off -dpms; xsetroot -solid '#0e2433'
matchbox-window-manager -use_titlebar no -use_cursor yes &
exec dbus-launch --exit-with-session surf -F file:///opt/marea/index.html
S
chmod +x $R/opt/marea/session.sh
cat > $R/etc/systemd/system/marea.service <<'S'
[Unit]
Description=Marea OS
After=systemd-user-sessions.service systemd-udev-settle.service
Conflicts=getty@tty7.service
[Service]
Environment=HOME=/root
TTYPath=/dev/tty7
StandardInput=tty
TTYReset=yes
TTYVHangup=yes
ExecStart=/usr/bin/xinit /opt/marea/session.sh -- /usr/bin/X :0 vt7 -nolisten tcp -keeptty
Restart=always
[Install]
WantedBy=multi-user.target
S
chroot $R systemctl enable marea.service
chroot $R systemctl set-default multi-user.target
echo marea > $R/etc/hostname
sed -i 's/^PRETTY_NAME=.*/PRETTY_NAME="Marea OS 1.0"/;s/^NAME=.*/NAME="Marea OS"/' $R/etc/os-release
chroot $R update-initramfs -u
K=$(ls $R/boot/vmlinuz-* | sort -V | tail -1); I=$(ls $R/boot/initrd.img-* | sort -V | tail -1)
cp $K $W/iso/casper/vmlinuz; cp $I $W/iso/casper/initrd
chroot $R apt-get clean; rm -rf $R/var/lib/apt/lists/* $R/usr/sbin/policy-rc.d
for m in dev/pts dev sys proc; do umount $R/$m; done
mksquashfs $R $W/iso/casper/filesystem.squashfs -comp xz -b 1M -e boot -noappend
cat > $W/iso/boot/grub/grub.cfg <<'S'
set timeout=3
set default=0
menuentry "Marea OS" {
 linux /casper/vmlinuz boot=casper quiet loglevel=3
 initrd /casper/initrd
}
menuentry "Marea OS (modo seguro, sin aceleración)" {
 linux /casper/vmlinuz boot=casper nomodeset loglevel=3
 initrd /casper/initrd
}
S
mkdir -p /mnt/user-data/outputs
grub-mkrescue -o /mnt/user-data/outputs/marea-os.iso $W/iso -- -volid MAREA_OS
echo BUILD_OK
