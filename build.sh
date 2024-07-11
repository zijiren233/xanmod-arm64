#!/bin/bash
set -e

LLVM=1

for i in "$@"; do
    case ${i,,} in
    --version=*)
        XANMODVER="${i#*=}"
        shift
        ;;
    --version)
        echo "Please use '--${i#--}=' to assign value to option"
        exit 1
        ;;
    --llvm=*)
        LLVM="${i#*=}"
        shift
        ;;
    --llvm)
        echo "Please use '--${i#--}=' to assign value to option"
        exit 1
        ;;
    -*)
        echo "Unknown option $i"
        exit 1
        ;;
    *) ;;
    esac
done

if [[ ! ${XANMODVER} =~ ^[0-9]+\.[0-9]+\.[0-9]+(-[a-z0-9]+)*-xanmod[0-9]+$ ]]; then
    echo "XANMODVER is not in format 'x.y.z(-something)-xanmodN'"
    exit 1
fi

echo "xanmod version: ${XANMODVER}"

apt update &&
    apt install -y wget make clang llvm lld \
        flex bison libncurses-dev perl libssl-dev:native \
        libelf-dev:native build-essential lsb-release \
        bc debhelper rsync kmod cpio

rm -rf "linux-${XANMODVER}.tar.gz"
wget "https://gitlab.com/xanmod/linux/-/archive/${XANMODVER}/linux-${XANMODVER}.tar.gz"
mkdir -p "linux-${XANMODVER}-kernel"
rm -rf "linux-${XANMODVER}-kernel/*"
tar -zxf "linux-${XANMODVER}.tar.gz" \
    -C "linux-${XANMODVER}-kernel" \
    --strip-components=1
cd "linux-${XANMODVER}-kernel"

cp ../configs/config-6.6.13+bpo-arm64 .config

scripts/config --set-str CONFIG_LOCALVERSION '-arm64'

scripts/config --disable DEBUG_INFO_DWARF_TOOLCHAIN_DEFAULT
scripts/config --set-val CONFIG_DEBUG_INFO_NONE y

# disable sig
scripts/config --set-str CONFIG_SYSTEM_TRUSTED_KEYS ''
scripts/config --set-str CONFIG_SYSTEM_REVOCATION_KEYS ''

scripts/config --disable CONFIG_DEBUG_INFO_BTF # then no need dwarves

# LTO
scripts/config --enable CONFIG_LTO_CLANG_THIN

# MODULE SIG SHA1
scripts/config --set-val CONFIG_MODULE_SIG_SHA1 y
scripts/config --set-str CONFIG_MODULE_SIG_HASH sha1
scripts/config --disable CONFIG_MODULE_SIG_SHA224
scripts/config --disable CONFIG_MODULE_SIG_SHA256
scripts/config --disable CONFIG_MODULE_SIG_SHA384
scripts/config --disable CONFIG_MODULE_SIG_SHA512

# BBR
scripts/config --set-val CONFIG_TCP_CONG_BBR y
scripts/config --set-str CONFIG_DEFAULT_TCP_CONG BBR

MAKE="make -j$(nproc) ARCH=arm64 LLVM=${LLVM} LLVM_IAS=1"

$MAKE olddefconfig

$MAKE
echo "build done"

echo "release deb"
$MAKE bindeb-pkg

mkdir -p debs
rm -rf debs/*

VER="${XANMODVER%-xanmod*}"
mv ../linux-headers-${VER}*.deb debs
mv ../linux-image-${VER}*.deb debs
mv ../linux-libc-dev_${VER}*.deb debs
mv ../linux-upstream_${VER}*.buildinfo debs
