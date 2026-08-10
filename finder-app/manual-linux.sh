#!/bin/bash
# Script outline to install and build kernel.
# Author: Siddhant Jajoo.

set -e
set -u

OUTDIR=/tmp/aeld
KERNEL_REPO=git://git.kernel.org/pub/scm/linux/kernel/git/stable/linux-stable.git
KERNEL_VERSION=v5.15.163
BUSYBOX_VERSION=1_33_1
FINDER_APP_DIR=$(realpath $(dirname $0))
ARCH=arm64
CROSS_COMPILE=aarch64-none-linux-gnu-
JOBS=$(nproc)

if [ $# -lt 1 ]
then
	echo "Using default directory ${OUTDIR} for output"
else
	OUTDIR=$1
	echo "Using passed directory ${OUTDIR} for output"
fi

mkdir -p ${OUTDIR}

cd "$OUTDIR"
if [ ! -d "${OUTDIR}/linux-stable" ]; then
    #Clone only if the repository does not exist.
	echo "CLONING GIT LINUX STABLE VERSION ${KERNEL_VERSION} IN ${OUTDIR}"
	git clone ${KERNEL_REPO} --depth 1 --single-branch --branch ${KERNEL_VERSION}
fi
if [ ! -e ${OUTDIR}/linux-stable/arch/${ARCH}/boot/Image ]; then
    cd linux-stable
    echo "Checking out version ${KERNEL_VERSION}"
    git checkout ${KERNEL_VERSION}

    # Kernel build steps (Module 2):
    #  1. mrproper  - remove any stale .config / build artifacts
    #  2. defconfig - generate the default arm64 config
    #  3. all       - build the kernel Image and device tree blobs
    # modules_install is intentionally skipped (see assignment note e.i).
    echo "Cleaning kernel build tree (mrproper)"
    make -j"$JOBS" ARCH=$ARCH CROSS_COMPILE=$CROSS_COMPILE mrproper

    echo "Configuring kernel (defconfig)"
    make -j"$JOBS" ARCH=$ARCH CROSS_COMPILE=$CROSS_COMPILE defconfig

    echo "Building kernel Image and device tree blobs (all)"
    make -j"$JOBS" ARCH=$ARCH CROSS_COMPILE=$CROSS_COMPILE all
fi

echo "Adding the Image in outdir"
cp "${OUTDIR}/linux-stable/arch/${ARCH}/boot/Image" "${OUTDIR}/Image"

echo "Creating the staging directory for the root filesystem"
cd "$OUTDIR"
if [ -d "${OUTDIR}/rootfs" ]
then
	echo "Deleting rootfs directory at ${OUTDIR}/rootfs and starting over"
    sudo rm  -rf ${OUTDIR}/rootfs
fi

# Create the base directory tree for the root filesystem.
echo "Creating base directories under ${OUTDIR}/rootfs"
mkdir -p "${OUTDIR}/rootfs"
cd "${OUTDIR}/rootfs"
mkdir -p bin dev etc home lib lib64 proc sbin sys tmp usr var
mkdir -p usr/bin usr/lib usr/sbin
mkdir -p var/log

cd "$OUTDIR"
if [ ! -d "${OUTDIR}/busybox" ]
then
git clone git://busybox.net/busybox.git
    cd busybox
    git checkout ${BUSYBOX_VERSION}
    # TODO:  Configure busybox
    echo "Configuring busy box"
    make \
     -j"$JOBS" \
     ARCH=$ARCH \
     CROSS_COMPILE=$CROSS_COMPILE \
     defconfig
else
    cd busybox
fi

# Build busybox, then install it into the rootfs staging tree. CONFIG_PREFIX
# points the install at ${OUTDIR}/rootfs so the applets land in rootfs/bin,
# rootfs/sbin, etc. (without it, busybox installs into its own _install dir).
echo "Building busybox"
make -j"$JOBS" \
     ARCH="$ARCH" \
     CROSS_COMPILE="$CROSS_COMPILE"

echo "Installing busybox into ${OUTDIR}/rootfs"
make ARCH="$ARCH" \
     CROSS_COMPILE="$CROSS_COMPILE" \
     CONFIG_PREFIX="${OUTDIR}/rootfs" \
     install

echo "Library dependencies"
# Run from the rootfs so the installed bin/busybox resolves.
cd "${OUTDIR}/rootfs"
${CROSS_COMPILE}readelf -a bin/busybox | grep "program interpreter"
${CROSS_COMPILE}readelf -a bin/busybox | grep "Shared library"

# TODO: Add library dependencies to rootfs
SYSROOT=$(${CROSS_COMPILE}gcc -print-sysroot)

# program interpreter -> /lib
cp -a "${SYSROOT}/lib/ld-linux-aarch64.so.1" "${OUTDIR}/rootfs/lib/"

# shared libraries -> /lib64
cp -a "${SYSROOT}/lib64/libm.so.6"      "${OUTDIR}/rootfs/lib64/"
cp -a "${SYSROOT}/lib64/libresolv.so.2" "${OUTDIR}/rootfs/lib64/"
cp -a "${SYSROOT}/lib64/libc.so.6"      "${OUTDIR}/rootfs/lib64/"

# TODO: Make device nodes
# Create the minimal set of device nodes the initramfs needs before init runs.
# These must exist statically in the cpio archive (there is no devtmpfs/udev
# yet at this point in boot). mknod needs root, hence sudo.
#   /dev/null    - char, major 1 minor 3  (the bit-bucket)
#   /dev/console - char, major 5 minor 1  (init's stdin/stdout/stderr)
echo "Making device nodes"
cd "${OUTDIR}/rootfs"
sudo mknod -m 666 dev/null    c 1 3
sudo mknod -m 600 dev/console c 5 1

# TODO: Clean and build the writer utility
echo "Building the writer utility (cross-compiled)"
cd "${FINDER_APP_DIR}"
make clean
make CROSS_COMPILE="${CROSS_COMPILE}"

# Copy the finder related scripts and executables to the /home directory on the
# target rootfs. cwd is still FINDER_APP_DIR from the writer build above, so the
# scripts are local and ../conf reaches the repo's conf/ directory.
echo "Copying finder scripts and conf files to rootfs/home"
cp writer "${OUTDIR}/rootfs/home/"
cp finder.sh finder-test.sh autorun-qemu.sh "${OUTDIR}/rootfs/home/"
mkdir -p "${OUTDIR}/rootfs/home/conf"
cp ../conf/username.txt ../conf/assignment.txt "${OUTDIR}/rootfs/home/conf/"

# f.i: on the target, finder-test.sh runs from /home, so point it at
# conf/assignment.txt (relative to /home) instead of ../conf/assignment.txt.
sed -i 's|\.\./conf/assignment.txt|conf/assignment.txt|' "${OUTDIR}/rootfs/home/finder-test.sh"

# TODO: Chown the root directory
# The rootfs was populated as the build user; a real root filesystem must be
# owned by root:root (uid 0). Fix ownership across the whole tree before it is
# packed into the initramfs. Needs root, hence sudo.
echo "Chowning rootfs to root:root"
sudo chown -R root:root "${OUTDIR}/rootfs"

# Create initramfs.cpio.gz from the staging tree. Must be built from INSIDE
# rootfs so the archive root is the filesystem root (./init, ./bin, ...), else
# the kernel panics with "VFS: Unable to mount root fs". --owner root:root bakes
# uid/gid 0 into the archive; -f on gzip allows clean re-runs.
echo "Creating initramfs.cpio.gz"
cd "${OUTDIR}/rootfs"
find . | cpio -H newc -o --owner root:root > "${OUTDIR}/initramfs.cpio"
gzip -f "${OUTDIR}/initramfs.cpio"
