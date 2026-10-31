#!/usr/bin/env bash
# Build android_kernel_LIO_kirin990_103 (5.10.43) with the HarmonyOS port patches.
# Same two adjustments as the Kirin 9000 build: export CONFIG_* and pass the
# modem include directories through KCFLAGS (platform_drivers path).
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "${REPO_ROOT}"

OUT_DIR="${OUT_DIR:-out}"
JOBS="${JOBS:-$(nproc)}"

echo "== applying port patches"
for p in patches/0001-binder-async-sender-pid.patch patches/0002-rdr-no-ap-reset.patch; do
    if git apply --check "$p" 2>/dev/null; then
        git apply "$p"; echo "   applied $(basename "$p")"
    elif patch -p1 --forward --dry-run < "$p" >/dev/null 2>&1; then
        patch -p1 --forward < "$p"; echo "   applied $(basename "$p") (patch)"
    else
        echo "   !! $(basename "$p") not applied"
    fi
done

echo "== toolchain wiring"
if [ ! -e /usr/bin/clang++ ]; then sudo ln -sf /usr/bin/clang++-12 /usr/bin/clang++; fi
for t in llvm-ar llvm-nm llvm-objcopy llvm-objdump llvm-readelf llvm-strip; do
    if [ ! -e "/usr/bin/$t" ]; then sudo ln -sf "/usr/bin/$t-12" "/usr/bin/$t"; fi
done
export CROSS_COMPILE=aarch64-linux-gnu-
CLANG_PREBUILTS_PATH=/usr/

echo "== configure (vendor defconfig)"
mkdir -p "${OUT_DIR}"
make ARCH=arm64 O="${OUT_DIR}" CLANG_PREBUILTS_PATH="${CLANG_PREBUILTS_PATH}" merge_kirin990_defconfig

echo "== adjust config"
scripts/config --file "${OUT_DIR}/.config" -d BALONG_ESPE || true
make ARCH=arm64 O="${OUT_DIR}" CLANG_PREBUILTS_PATH="${CLANG_PREBUILTS_PATH}" olddefconfig

echo "== export CONFIG_* as make variables"
# shellcheck disable=SC2046
export $(grep -E '^CONFIG_[A-Za-z0-9_]+=y$' "${OUT_DIR}/.config" | tr -d '\r')

MODEM_INC="-Idrivers/hisi/modem/drv/icc \
 -Idrivers/hisi/modem/drv/balong_timer \
 -Idrivers/hisi/modem/drv/hds \
 -Idrivers/hisi/modem/drv/diag/cpm \
 -Idrivers/hisi/tzdriver \
 -Idrivers/hisi/modem/drv/include"

echo "== build"
make -j"${JOBS}" ARCH=arm64 O="${OUT_DIR}" \
     CLANG_PREBUILTS_PATH="${CLANG_PREBUILTS_PATH}" \
     KCFLAGS="${MODEM_INC}" \
     Image.gz Image

echo "== artifacts"
ls -l "${OUT_DIR}/arch/arm64/boot/Image.gz" "${OUT_DIR}/arch/arm64/boot/Image" 2>/dev/null || true
grep -E "CONFIG_HISI_BALONG_MODEM|CONFIG_BINDER_TRANSACTION_PROC_BRIEF" "${OUT_DIR}/.config" || true
