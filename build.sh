#!/usr/bin/env bash
# =============================================================================
#  build.sh — Multi-Variant Kernel Builder for Xiaomi Earth (MT6768 / 4.19)
#  Produces optional flashable zips: vanilla | ksu-next | sukisu
#
#  Source management: KernelSU-Next and SukiSU are git submodules.
#  KernelSU/ is a symlink (committed) that is swapped at build time.
#
#  Usage:
#    ./build.sh                        → build ALL three variants
#    ./build.sh vanilla                → vanilla only (no root)
#    ./build.sh ksu-next               → KSU-Next only
#    ./build.sh sukisu                 → SukiSU-Ultra only
#    ./build.sh ksu-next sukisu        → two specific variants
# =============================================================================

set -euo pipefail

# ── Paths ────────────────────────────────────────────────────────────────────
KERNEL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OUT_DIR="${KERNEL_DIR}/out"
AK3_DIR="${KERNEL_DIR}/AnyKernel3"
RELEASES_DIR="${KERNEL_DIR}/releases"
DEFCONFIG="earth_defconfig"
MAKEFILE="${KERNEL_DIR}/Makefile"

# ── OS-aware toolchain detection ─────────────────────────────────────────────
if [[ "$(uname)" == "Darwin" ]]; then
  LLVM_BIN="/opt/homebrew/opt/llvm/bin"
  CROSS_COMPILE="aarch64-elf-"
  JOBS="$(sysctl -n hw.logicalcpu)"
  PATH="${LLVM_BIN}:/opt/homebrew/bin:${PATH}"
else
  # Linux (GitHub Actions / Ubuntu)
  # Find the highest installed LLVM version
  LLVM_VER="$(ls /usr/lib/llvm-*/bin/clang 2>/dev/null | grep -oP '(?<=llvm-)\d+' | sort -rn | head -1)"
  if [[ -n "${LLVM_VER}" ]]; then
    LLVM_BIN="/usr/lib/llvm-${LLVM_VER}/bin"
  else
    LLVM_BIN="/usr/bin"
  fi
  CROSS_COMPILE="aarch64-linux-gnu-"
  JOBS="$(nproc)"
  PATH="${LLVM_BIN}:${PATH}"
fi
export PATH

DATE="$(date +%Y%m%d)"

# ── Variant source directories ────────────────────────────────────────────────
declare -A VARIANT_DIRS=(
  [ksu-next]="KernelSU-Next"
  [sukisu]="SukiSU"
)

declare -A VARIANT_LABELS=(
  [vanilla]="Vanilla (No Root)"
  [ksu-next]="KernelSU-Next"
  [sukisu]="SukiSU-Ultra"
)

# ── Colors ────────────────────────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; BOLD='\033[1m'; RESET='\033[0m'

log()  { echo -e "${CYAN}[BUILD]${RESET} $*"; }
ok()   { echo -e "${GREEN}[  OK ]${RESET} $*"; }
warn() { echo -e "${YELLOW}[ WARN]${RESET} $*"; }
err()  { echo -e "${RED}[ERROR]${RESET} $*" >&2; exit 1; }

# ── Sanity checks ─────────────────────────────────────────────────────────────
check_deps() {
  [[ -f "${LLVM_BIN}/clang" ]] || \
    err "Clang not found at ${LLVM_BIN}/clang (uname: $(uname))"
  command -v "${CROSS_COMPILE}gcc" &>/dev/null || \
    err "Cross-compiler ${CROSS_COMPILE}gcc not found in PATH"
  [[ -d "${AK3_DIR}" ]]         || err "AnyKernel3 directory not found"
  [[ -f "${MAKEFILE}" ]]        || err "Not inside a kernel source tree"
  [[ -d "${KERNEL_DIR}/KernelSU-Next/kernel" ]] || \
    err "KernelSU-Next submodule not initialised — run: git submodule update --init --recursive"
  [[ -d "${KERNEL_DIR}/SukiSU/kernel" ]] || \
    err "SukiSU submodule not initialised — run: git submodule update --init --recursive"
}

# ── KernelSU Makefile toggle (vanilla: no KSU module) ────────────────────────
ksu_disable() {
  log "Disabling KernelSU module in Makefile (vanilla build)"
  sed -i.bak 's|^\(core-y.*+= KernelSU/kernel/\)|# \1|' "${MAKEFILE}"
  sed -i.bak 's|^\(KernelSU/kernel: security\)|# \1|' "${MAKEFILE}"
  rm -f "${MAKEFILE}.bak"
}

ksu_enable() {
  log "Re-enabling KernelSU module in Makefile"
  sed -i.bak 's|^# \(core-y.*+= KernelSU/kernel/\)|\1|' "${MAKEFILE}"
  sed -i.bak 's|^# \(KernelSU/kernel: security\)|\1|' "${MAKEFILE}"
  rm -f "${MAKEFILE}.bak"
}

# ── Symlink swap (for ksu-next / sukisu) ──────────────────────────────────────
swap_ksu() {
  local target="$1"
  log "Switching KernelSU/ → ${target}"
  rm -f "${KERNEL_DIR}/KernelSU"
  ln -s "${target}" "${KERNEL_DIR}/KernelSU"
  ok "KernelSU/ → ${target}"
}

# ── Build kernel ──────────────────────────────────────────────────────────────
build_kernel() {
  local label="${VARIANT_LABELS[$1]}"

  echo ""
  echo -e "${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
  echo -e "${BOLD}  Building: ${label}${RESET}"
  echo -e "${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"

  local MAKE_FLAGS=(
    -j"${JOBS}"
    O="${OUT_DIR}"
    ARCH=arm64
    LLVM=1
    LLVM_IAS=1
    CC="${LLVM_BIN}/clang"
    LD="${LLVM_BIN}/ld.lld"
    AR="${LLVM_BIN}/llvm-ar"
    NM="${LLVM_BIN}/llvm-nm"
    OBJCOPY="${LLVM_BIN}/llvm-objcopy"
    OBJDUMP="${LLVM_BIN}/llvm-objdump"
    READELF="${LLVM_BIN}/llvm-readelf"
    STRIP="${LLVM_BIN}/llvm-strip"
    CROSS_COMPILE="${CROSS_COMPILE}"
  )

  log "Generating defconfig (${DEFCONFIG})..."
  make "${MAKE_FLAGS[@]}" "${DEFCONFIG}"

  log "Compiling kernel (${JOBS} threads)..."
  local start_time=$SECONDS
  make "${MAKE_FLAGS[@]}"
  local elapsed=$(( SECONDS - start_time ))
  ok "Kernel compiled in ${elapsed}s"
}

# ── Package zip ───────────────────────────────────────────────────────────────
package_zip() {
  local variant="$1"
  local label="${VARIANT_LABELS[$variant]}"
  local image="${OUT_DIR}/arch/arm64/boot/Image.gz-dtb"
  local zip_name="kernel-earth-${variant}-${DATE}.zip"
  local zip_path="${RELEASES_DIR}/${zip_name}"

  [[ -f "$image" ]] || err "Image.gz-dtb not found after build: ${image}"

  log "Copying Image.gz-dtb to AnyKernel3..."
  cp "$image" "${AK3_DIR}/Image.gz-dtb"

  log "Updating kernel.string in anykernel.sh..."
  sed -i.bak "s|^kernel\.string=.*|kernel.string=Earth Kernel [${label}] by Mubashar Dev|" \
    "${AK3_DIR}/anykernel.sh"
  rm -f "${AK3_DIR}/anykernel.sh.bak"

  log "Packaging ${zip_name}..."
  mkdir -p "${RELEASES_DIR}"
  (
    cd "${AK3_DIR}"
    zip -r9 "${zip_path}" . \
      --exclude '*.git*' \
      --exclude '*.DS_Store*' \
      --exclude '*.github*'
  )

  unzip -t "${zip_path}" &>/dev/null || err "Zip validation failed: ${zip_path}"

  local size
  size=$(du -sh "${zip_path}" | cut -f1)
  ok "Created: ${zip_name} (${size})"
  echo "   📦 ${zip_path}"
}

# ── Per-variant setup + teardown ──────────────────────────────────────────────
setup_variant() {
  local variant="$1"
  case "$variant" in
    vanilla)
      ksu_disable
      ;;
    ksu-next|sukisu)
      local src="${VARIANT_DIRS[$variant]}"
      [[ -d "${KERNEL_DIR}/${src}/kernel" ]] || \
        err "'${src}/kernel' subdir missing — did submodules initialise?"
      swap_ksu "$src"
      ksu_enable
      ;;
  esac
}

teardown_variant() {
  local variant="$1"
  [[ "$variant" == "vanilla" ]] && ksu_enable || true
}

build_variant() {
  local variant="$1"
  setup_variant "$variant"
  build_kernel "$variant"
  package_zip "$variant"
  teardown_variant "$variant"
}

# ── Entry point ───────────────────────────────────────────────────────────────
main() {
  cd "${KERNEL_DIR}"
  check_deps

  local variants=()
  if [[ $# -eq 0 ]]; then
    variants=(vanilla ksu-next sukisu)
    log "No variant specified — building ALL variants"
  else
    for arg in "$@"; do
      case "$arg" in
        vanilla|ksu-next|sukisu) variants+=("$arg") ;;
        *) err "Unknown variant '${arg}'. Valid: vanilla | ksu-next | sukisu" ;;
      esac
    done
  fi

  local built=(); local failed=()
  local total_start=$SECONDS

  # Restore Makefile + symlink on any exit
  trap 'ksu_enable 2>/dev/null; swap_ksu KernelSU-Next 2>/dev/null
        echo -e "\n${RED}Interrupted — state restored${RESET}"' ERR INT TERM

  for variant in "${variants[@]}"; do
    if build_variant "$variant"; then
      built+=("$variant")
    else
      warn "Build failed for variant: ${variant}"
      failed+=("$variant")
    fi
  done

  trap - ERR INT TERM

  # Always restore to ksu-next default
  swap_ksu "KernelSU-Next"
  ksu_enable

  local total_elapsed=$(( SECONDS - total_start ))
  echo ""
  echo -e "${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
  echo -e "${BOLD}  Build Summary (${total_elapsed}s total)${RESET}"
  echo -e "${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
  for v in "${built[@]}"; do echo -e "  ${GREEN}✓${RESET} ${VARIANT_LABELS[$v]}"; done
  for v in "${failed[@]}"; do echo -e "  ${RED}✗${RESET} ${VARIANT_LABELS[$v]}"; done

  echo ""
  if [[ ${#built[@]} -gt 0 ]]; then
    echo -e "  Output: ${BOLD}${RELEASES_DIR}/${RESET}"
    ls -lh "${RELEASES_DIR}"/kernel-earth-*-"${DATE}".zip 2>/dev/null \
      | awk '{print "  📦 "$NF" ("$5")"}' || true
  fi

  [[ ${#failed[@]} -eq 0 ]] || exit 1
}

main "$@"
