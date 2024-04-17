#!/bin/bash

#CRBL_INITIALIZE
#CRBL_HEADLESS

set -ex

if [ -z "$1" ]; then
	echo "$0 TARGET"
	exit 1
fi

CRBL_TARGET="$1"

if [ -z "$CRBL_INITIALIZE" ]; then
	if [ ! -e "$CRBL_TARGET" ]; then
		echo "TARGET $1 does not exist."
		exit 1
	fi
elif [ ! -e "$CRBL_TARGET" ]; then
	truncate -s 5G $CRBL_TARGET
fi

if [ -f "$CRBL_TARGET" ]; then
	CRBL_TARGET=$(sudo losetup --show -f "$CRBL_TARGET")
	CRBL_LOOP_DEV=1
fi

if [ ! -w "$CRBL_TARGET" ]; then
	echo "TARGET $1 is not writable."
	exit 1
fi

CRBL_DISTRO=debian
CRBL_DEB_SUITE=bookworm
CRBL_ARCH=arm64

CRBL_PART_KERN_A=1
CRBL_PART_KERN_B=2
CRBL_PART_BOOT=3
CRBL_PART_ROOT=4

CRBL_PART_SIZE_OFFSET=4
CRBL_PART_SIZE_KERN_A=62
CRBL_PART_SIZE_KERN_B=62
CRBL_PART_SIZE_BOOT=$((512-CRBL_PART_SIZE_OFFSET-CRBL_PART_SIZE_KERN_A-CRBL_PART_SIZE_KERN_B))
CRBL_PART_SIZE_ROOT=$((4*1024+512))

CRBL_PART_LABEL_KERN_A="KERN-A"
CRBL_PART_LABEL_KERN_B="KERN-B"
CRBL_PART_LABEL_BOOT="BOOT"
CRBL_PART_LABEL_ROOT="ROOT"

CRBL_PART_MP_ROOT=$PWD/root
CRBL_PART_MP_BOOT=$PWD/root/boot/EFI
CRBL_DIR_LINUX=$PWD/linux
CRBL_DIR_LINUX_FW=$PWD/linux-firmware

if [ -z "$CRBL_DEPTHCHARGE_COMP" ]; then
	CRBL_DEPTHCHARGE_COMP=lzma
fi

CRBL_PART_PREFIX=
CRBL_PART_ALT_SCAN=
if [ "${CRBL_TARGET:5:6}" = "mmcblk" ]; then
	CRBL_PART_PREFIX=p
elif [ "${CRBL_TARGET:5:4}" = "nvme" ]; then
	CRBL_PART_PREFIX=p
elif [ "${CRBL_TARGET:5:4}" = "loop" ]; then
	CRBL_PART_PREFIX=p
	CRBL_PART_ALT_SCAN=1
fi

if [ -z "$CRBL_PART_ALT_SCAN" ]; then
	DISK_SEC_SIZE=$(blockdev --getss "$CRBL_TARGET")
else
	DISK_SEC_SIZE=512
fi
DISK_SEC_PER_MB=$((1024*1024/DISK_SEC_SIZE))
DISK_GPT_SIZE=$((32*1024/DISK_SEC_SIZE))

if [ ! -z "$CRBL_INITIALIZE" ]; then
	sudo cgpt create "$CRBL_TARGET"
	sudo cgpt add -i $CRBL_PART_KERN_A -b $((CRBL_PART_SIZE_OFFSET*DISK_SEC_PER_MB)) -s $((CRBL_PART_SIZE_KERN_A*DISK_SEC_PER_MB)) -t kernel -l "$CRBL_PART_LABEL_KERN_A" "$CRBL_TARGET"
	CRBL_PART_SIZE_OFFSET=$((CRBL_PART_SIZE_OFFSET+CRBL_PART_SIZE_KERN_A))
	sudo cgpt add -i $CRBL_PART_KERN_B -b $((CRBL_PART_SIZE_OFFSET*DISK_SEC_PER_MB)) -s $((CRBL_PART_SIZE_KERN_B*DISK_SEC_PER_MB)) -t kernel -l "$CRBL_PART_LABEL_KERN_B" "$CRBL_TARGET"
	CRBL_PART_SIZE_OFFSET=$((CRBL_PART_SIZE_OFFSET+CRBL_PART_SIZE_KERN_B))
	sudo cgpt add -i $CRBL_PART_BOOT -b $((CRBL_PART_SIZE_OFFSET*DISK_SEC_PER_MB)) -s $((CRBL_PART_SIZE_BOOT*DISK_SEC_PER_MB)) -t efi -l "$CRBL_PART_LABEL_BOOT" "$CRBL_TARGET"
	CRBL_PART_SIZE_OFFSET=$((CRBL_PART_SIZE_OFFSET+CRBL_PART_SIZE_BOOT))
	sudo cgpt add -i $CRBL_PART_ROOT -b $((CRBL_PART_SIZE_OFFSET*DISK_SEC_PER_MB)) -s $((CRBL_PART_SIZE_ROOT*DISK_SEC_PER_MB-DISK_GPT_SIZE)) -t data -l "$CRBL_PART_LABEL_ROOT" "$CRBL_TARGET"
	sudo cgpt boot -i $CRBL_PART_BOOT -p "$CRBL_TARGET"
	if [ -z "$CRBL_PART_ALT_SCAN" ]; then
		sudo blockdev --rereadpt "$CRBL_TARGET"
	else
		sudo partprobe "$CRBL_TARGET"
	fi
	sudo mkfs.vfat -F 32 -n "$CRBL_PART_LABEL_BOOT" "$CRBL_TARGET$CRBL_PART_PREFIX$CRBL_PART_BOOT"
	sudo mkfs.btrfs -L "$CRBL_PART_LABEL_ROOT" -f "$CRBL_TARGET$CRBL_PART_PREFIX$CRBL_PART_ROOT"
fi

#BTRFS ROOT AND BOOT
mkdir -p "$CRBL_PART_MP_ROOT"
sudo mount -o noatime,compress=zstd "$CRBL_TARGET$CRBL_PART_PREFIX$CRBL_PART_ROOT" "$CRBL_PART_MP_ROOT"
if sudo btrfs subvolume get-default "$CRBL_PART_MP_ROOT" | grep FS_TREE > /dev/null; then
	sudo btrfs subvolume create "$CRBL_PART_MP_ROOT/@"
	sudo btrfs subvolume set-default "$CRBL_PART_MP_ROOT/@"
	sudo umount "$CRBL_PART_MP_ROOT"
	sudo mount -o noatime,compress=zstd "$CRBL_TARGET$CRBL_PART_PREFIX$CRBL_PART_ROOT" "$CRBL_PART_MP_ROOT"
fi

#DEBOOTSTRAP
if [ ! -d "$CRBL_PART_MP_ROOT/home" ]; then
	CRBL_DEB_PACKAGES=eatmydata,btrfs-progs,kbd,keyboard-configuration,locales,initramfs-tools
	if [ -z "$CRBL_HEADLESS" ]; then
		CRBL_PACKAGES+=,task-gnome-desktop,gnome-initial-setup
	fi
	sudo eatmydata mmdebstrap --components main,contrib,non-free,non-free-firmware --include "$CRBL_DEB_PACKAGES" "$CRBL_DEB_SUITE" "$CRBL_PART_MP_ROOT"
fi

echo "chromebook-linux" | sudo tee "$CRBL_PART_MP_ROOT/etc/hostname"
echo "LABEL=$CRBL_PART_LABEL_ROOT / btrfs defaults,ssd,compress=zstd,noatime 0 0" | sudo tee "$CRBL_PART_MP_ROOT/etc/fstab"
echo "LABEL=$CRBL_PART_LABEL_BOOT /boot/efi vfat defaults,noatime 0 1" | sudo tee -a "$CRBL_PART_MP_ROOT/etc/fstab"

#cat "$CRBL_DISTRO/apt/$CRBL_DEB_SUITE/sources.list" | sudo tee "$CRBL_PART_MP_ROOT/etc/apt/sources.list"
sudo sed -i "s/^XKBMODEL=\".*\"/XKBMODEL=\"chromebook\"/" "$CRBL_PART_MP_ROOT/etc/default/keyboard"
sudo sed -i "s/\(# \)\\?en_US.UTF-8/en_US.UTF-8/" "$CRBL_PART_MP_ROOT/etc/locale.gen"
sudo chroot "$CRBL_PART_MP_ROOT" locale-gen

if [ ! -z "$CRBL_HEADLESS" ]; then
	echo "root:root" | sudo chroot "$CRBL_PART_MP_ROOT" chpasswd
	sudo chroot "$CRBL_PART_MP_ROOT" passwd -e root
fi

#LINUX
CRBL_LINUX_VER=$(make -sC "$CRBL_DIR_LINUX" kernelversion)
if [ -z "$CRBL_LINUX_VER" ]; then
	echo "LINUX VERSION ERROR!"
	exit 1
fi

if [ -z "$LINUX_MENUCONFIG" ]; then
	make -C "$CRBL_DIR_LINUX" defconfig
else
	make -C "$CRBL_DIR_LINUX" menuconfig
	make -C "$CRBL_DIR_LINUX" savedefconfig
	mv "$CRBL_DIR_LINUX/defconfig" "$CRBL_DIR_LINUX/arch/$CRBL_ARCH/configs/defconfig"
fi

if [ -z "$LINUX_MAKE_SKIP" ]; then
	sudo eatmydata make -C "$CRBL_DIR_LINUX" -j`nproc --all`
fi
if [ -z "$LINUX_INSTALL_SKIP" ]; then
	sudo eatmydata make -C "$CRBL_DIR_LINUX" install INSTALL_PATH="$CRBL_PART_MP_ROOT/boot"
	sudo eatmydata make -C "$CRBL_DIR_LINUX" modules_install INSTALL_MOD_PATH="$CRBL_PART_MP_ROOT"
	sudo eatmydata make -C "$CRBL_DIR_LINUX" headers_install INSTALL_HDR_PATH="$CRBL_PART_MP_ROOT/usr"
fi

#LINUX FIRMWARE
if [ -z "$LINUX_FIRMWARE_SKIP" ]; then
	sudo eatmydata make -C "$CRBL_DIR_LINUX_FW" install DESTDIR="$CRBL_PART_MP_ROOT"
fi

#INITRAMFS
sudo mount -o bind /dev "$CRBL_PART_MP_ROOT/dev"
sudo mount -o bind /dev/pts "$CRBL_PART_MP_ROOT/dev/pts"
sudo chroot "$CRBL_PART_MP_ROOT" mount -t proc proc /proc
sudo chroot "$CRBL_PART_MP_ROOT" mount -t sysfs sys /sys
sudo chroot "$CRBL_PART_MP_ROOT" update-initramfs -c -k "$CRBL_LINUX_VER"
sudo chroot "$CRBL_PART_MP_ROOT" umount /sys
sudo chroot "$CRBL_PART_MP_ROOT" umount /proc
sudo umount "$CRBL_PART_MP_ROOT/dev/pts"
sudo umount "$CRBL_PART_MP_ROOT/dev"


#DEPTHCHARGE
dd if=/dev/zero of=bootloader.bin bs=512 count=1
mkdepthcharge -o kernel.img --bootloader bootloader.bin \
	--format fit -C "$CRBL_DEPTHCHARGE_COMP" -A "$CRBL_ARCH" \
	-c "console=tty1 root=PARTUUID=%U/PARTNROFF=3 rootwait ro noresume" -- \
	"$CRBL_PART_MP_ROOT/boot/vmlinuz-$CRBL_LINUX_VER" \
	"$CRBL_PART_MP_ROOT/boot/initrd.img-$CRBL_LINUX_VER" \
	"$CRBL_DIR_LINUX/arch/$CRBL_ARCH/boot/dts/mediatek/mt8183-evb.dts" \
	"$CRBL_DIR_LINUX/arch/$CRBL_ARCH/boot/dts/mediatek/mt8183-kukui-jacuzzi-fennel14.dtb" \
	"$CRBL_DIR_LINUX/arch/$CRBL_ARCH/boot/dts/mediatek/mt8183-kukui-jacuzzi-fennel14-sku2.dtb" \
	"$CRBL_DIR_LINUX/arch/$CRBL_ARCH/boot/dts/mediatek/mt8186-evb.dts" \
	"$CRBL_DIR_LINUX/arch/$CRBL_ARCH/boot/dts/mediatek/mt8186-corsola-magneton-sku393216.dts" \
	"$CRBL_DIR_LINUX/arch/$CRBL_ARCH/boot/dts/mediatek/mt8186-corsola-magneton-sku393217.dts" \
	"$CRBL_DIR_LINUX/arch/$CRBL_ARCH/boot/dts/mediatek/mt8186-corsola-magneton-sku393218.dts" \
	"$CRBL_DIR_LINUX/arch/$CRBL_ARCH/boot/dts/mediatek/mt8188-evb.dts" \
	"$CRBL_DIR_LINUX/arch/$CRBL_ARCH/boot/dts/mediatek/mt8192-evb.dts" \
	"$CRBL_DIR_LINUX/arch/$CRBL_ARCH/boot/dts/mediatek/mt8192-asurada-spherion-r0.dts" \
	"$CRBL_DIR_LINUX/arch/$CRBL_ARCH/boot/dts/mediatek/mt8192-asurada-spherion-r4.dts" \
	"$CRBL_DIR_LINUX/arch/$CRBL_ARCH/boot/dts/mediatek/mt8195-evb.dts" \
	"$CRBL_DIR_LINUX/arch/$CRBL_ARCH/boot/dts/mediatek/mt8195-cherry-tomato-r1.dts" \
	"$CRBL_DIR_LINUX/arch/$CRBL_ARCH/boot/dts/mediatek/mt8195-cherry-tomato-r2.dts" \
	"$CRBL_DIR_LINUX/arch/$CRBL_ARCH/boot/dts/mediatek/mt8195-cherry-tomato-r3.dts" \
	"$CRBL_DIR_LINUX/arch/$CRBL_ARCH/boot/dts/mediatek/mt8395-genio-1200-evk.dts"

sudo dd if=kernel.img of="$CRBL_TARGET$CRBL_PART_PREFIX$CRBL_PART_KERN_A" bs=1M
sudo cgpt add -i $CRBL_PART_KERN_A -S 1 -T 0 -P 3 "$CRBL_TARGET"

#FINISH
sudo umount "$CRBL_PART_MP_ROOT"
if [ ! -z "$CRBL_LOOP_DEV" ]; then
	sudo losetup -d "$CRBL_TARGET"
fi
