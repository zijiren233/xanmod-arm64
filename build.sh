#!/bin/bash
set -e

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
        bc debhelper rsync kmod cpio libtinfo5
if ! command -v rustup >/dev/null 2>&1; then
    curl https://sh.rustup.rs -sSf | bash -s -- -y
fi
rustup default stable

rm -rf "linux-${XANMODVER}.tar.gz"
wget "https://gitlab.com/xanmod/linux/-/archive/${XANMODVER}/linux-${XANMODVER}.tar.gz"
mkdir -p "linux-${XANMODVER}-kernel"
rm -rf "linux-${XANMODVER}-kernel/*"
tar -zxf "linux-${XANMODVER}.tar.gz" \
    -C "linux-${XANMODVER}-kernel" \
    --strip-components=1
cd "linux-${XANMODVER}-kernel"

if [[ ${XANMODVER} =~ -rt ]]; then
    cp ../configs/config-6.9.7+bpo-rt-arm64 .config
else
    cp ../configs/config-6.9.7+bpo-arm64 .config
fi

undefine() {
    for _config_name in "$@"; do
        scripts/config -k --undefine "${_config_name}"
    done
}

enable() {
    for _config_name in "$@"; do
        scripts/config -k --enable "${_config_name}"
    done
}

disable() {
    for _config_name in "$@"; do
        scripts/config -k --disable "${_config_name}"
    done
}

module() {
    for _config_name in "$@"; do
        scripts/config -k --module "${_config_name}"
    done
}

# debug
disable DEBUG_INFO_DWARF_TOOLCHAIN_DEFAULT
disable DEBUG_INFO
enable DEBUG_INFO_NONE
disable "SLUB_DEBUG" "PM_DEBUG" "PM_ADVANCED_DEBUG" "PM_SLEEP_DEBUG" "ACPI_DEBUG" "SCHED_DEBUG" "LATENCYTOP" "DEBUG_PREEMPT"

# ftrace
disable "FUNCTION_TRACER" "FUNCTION_GRAPH_TRACER"

# tickless
disable "NO_HZ_FULL_NODEF" "HZ_PERIODIC" "NO_HZ_FULL" "TICK_CPU_ACCOUNTING" "CONTEXT_TRACKING_FORCE"
enable "NO_HZ_IDLE" "NO_HZ" "NO_HZ_COMMON" "CONTEXT_TRACKING" "VIRT_CPU_ACCOUNTING" "VIRT_CPU_ACCOUNTING_GEN"

# debian/ubuntu don't properly support zstd module compression
disable MODULE_COMPRESS_NONE
disable MODULE_COMPRESS_ZSTD
disable MODULE_COMPRESS_GZIP
enable MODULE_COMPRESS_XZ

# cpu gov performance
disable "CPU_FREQ_DEFAULT_GOV_SCHEDUTIL"
enable "CPU_FREQ_DEFAULT_GOV_PERFORMANCE" "CPU_FREQ_DEFAULT_GOV_PERFORMANCE_NODEF"
# cpu gov ondemand
# disable "CPU_FREQ_DEFAULT_GOV_SCHEDUTIL"
# enable "CPU_FREQ_DEFAULT_GOV_ONDEMAND" "CPU_FREQ_GOV_ONDEMAND"

# disable sig
scripts/config --set-str CONFIG_SYSTEM_TRUSTED_KEYS ''
scripts/config --set-str CONFIG_SYSTEM_REVOCATION_KEYS ''

# then no need dwarves
disable DEBUG_INFO_BTF

# LTO
disable LTO_CLANG_FULL
enable LTO_CLANG_THIN
disable LTO_NONE

# MODULE SIG SHA1
scripts/config --set-str CONFIG_MODULE_SIG_HASH sha1
enable MODULE_SIG_SHA1
disable MODULE_SIG_SHA224
disable MODULE_SIG_SHA256
disable MODULE_SIG_SHA384
disable MODULE_SIG_SHA512

# bbr
enable "TCP_CONG_ADVANCED"
_tcp_cong_alg_list=("yeah" "bbr" "cubic" "vegas" "westwood" "reno")
for _alg in "${_tcp_cong_alg_list[@]}"; do
    _alg_upper=$(echo "$_alg" | tr '[a-z]' '[A-Z]')
    enable "TCP_CONG_${_alg_upper}"
    disable "DEFAULT_${_alg_upper}"
done
enable "DEFAULT_BBR"
scripts/config --set-str "DEFAULT_TCP_CONG" "bbr"

LOCALVERSION="-arm64"
INSTALL_DIR="${PWD}/install"
PKGS_DIR="${PWD}/pkgs"
TAR_PKG="${PKGS_DIR}/kernel-${XANMODVER}${LOCALVERSION}.tar.gz2"

mkdir -p ${INSTALL_DIR}
rm -rf ${INSTALL_DIR}/*
mkdir -p ${INSTALL_DIR}/boot
mkdir -p ${PKGS_DIR}
rm -rf ${PKGS_DIR}/*

MAKE="make \
-j$(nproc) \
ARCH=arm64 \
LLVM=1 LLVM_IAS=1 \
INSTALL_PATH=$INSTALL_DIR/boot \
INSTALL_MOD_PATH=$INSTALL_DIR \
INSTALL_MOD_STRIP=1 \
LOCALVERSION=$LOCALVERSION EXTRAVERSION="" \
KCFLAGS=-pipe \
"

echo "make: $MAKE"

echo "clang version: $(clang --version)"

$MAKE olddefconfig

$MAKE prepare

$MAKE
echo "build done"

$MAKE modules

$MAKE install

$MAKE modules_install

echo "making tarball ..."
(cd "$INSTALL_DIR" && tar -czf "$TAR_PKG" boot/* lib/modules/* --owner=0 --group=0)

echo "release bindeb pkgs"
$MAKE bindeb-pkg

VER=$(echo ${XANMODVER} | cut -d- -f1)
mv ../linux-headers-${VER}*.deb $PKGS_DIR
mv ../linux-image-${VER}*.deb $PKGS_DIR
mv ../linux-libc-dev_${VER}*.deb $PKGS_DIR
mv ../linux-upstream_${VER}*.buildinfo $PKGS_DIR
