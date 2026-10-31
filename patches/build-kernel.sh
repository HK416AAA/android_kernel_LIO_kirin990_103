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
for p in patches/0*.patch; do
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


echo "== ccache wrapper"
WRAP="${RUNNER_TEMP:-/tmp}/clangwrap"
mkdir -p "$WRAP"
for tool in clang clang++ ld.lld llvm-ar llvm-nm llvm-objcopy llvm-objdump llvm-readelf llvm-strip; do
    case "$tool" in
        clang|clang++) printf '#!/bin/sh\nexec ccache /usr/bin/%s "$@"\n' "$tool" > "$WRAP/$tool" ;;
        *)             printf '#!/bin/sh\nexec /usr/bin/%s "$@"\n' "$tool" > "$WRAP/$tool" ;;
    esac
    chmod +x "$WRAP/$tool"
done
export PATH="$WRAP:$PATH"

echo "== configure (vendor defconfig)"
mkdir -p "${OUT_DIR}"
make ARCH=arm64 O="${OUT_DIR}" CLANG_PREBUILTS_PATH="${CLANG_PREBUILTS_PATH}" merge_kirin990_defconfig

echo "== adjust config"
echo "== disable only the subsystems that need the vendor GCC chain"
# NOTE: HUAWEI_AUDIO must stay enabled -- it provides the fsa4480/get_phy_addr
# symbols that other modules link against. Only virtual_voice_proxy fails to
# compile (its mailbox ids are not in the published tree).
for sym in HISI_BALONG_MODEM HISI_BALONG_MODEM_HI3650 MODEM_DRIVER BALONG_ESPE SOUND \
           VIRTUAL_VOICE_PROXY; do
    scripts/config --file "${OUT_DIR}/.config" -d "$sym" || true
done
make ARCH=arm64 O="${OUT_DIR}" CLANG_PREBUILTS_PATH="${CLANG_PREBUILTS_PATH}" olddefconfig

echo "== export CONFIG_* as make variables"
# shellcheck disable=SC2046
export $(grep -E '^CONFIG_[A-Za-z0-9_]+=y$' "${OUT_DIR}/.config" | tr -d '\r')


echo "== build"
make -k -j"${JOBS}" ARCH=arm64 O="${OUT_DIR}" \
     CLANG_PREBUILTS_PATH="${CLANG_PREBUILTS_PATH}" \
     Image.gz Image

echo "== artifacts"
ls -l "${OUT_DIR}/arch/arm64/boot/Image.gz" "${OUT_DIR}/arch/arm64/boot/Image" 2>/dev/null || true
grep -E "CONFIG_HISI_BALONG_MODEM|CONFIG_BINDER_TRANSACTION_PROC_BRIEF" "${OUT_DIR}/.config" || true
