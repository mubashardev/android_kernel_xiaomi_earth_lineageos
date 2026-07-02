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
  LD_BIN="/opt/homebrew/bin/ld.lld"
  PATH="${LLVM_BIN}:/opt/homebrew/bin:${PATH}"
else
  LLVM_BIN="/usr/lib/llvm-17/bin"   # Ubuntu llvm-17
  CROSS_COMPILE="aarch64-linux-gnu-"
  JOBS="$(nproc)"
  LD_BIN="${LLVM_BIN}/ld.lld"
  PATH="${LLVM_BIN}:${PATH}"
fi
export PATH

DATE="$(date +%Y%m%d)"

# ── Variant source directories ────────────────────────────────────────────────
declare -A VARIANT_DIRS=(
  [ksu-next]="KernelSU-Next"
  [sukisu]="SukiSU"
  [ksu-next+susfs]="KernelSU-Next"
  [sukisu-ultra+susfs]="SukiSU"
)

declare -A VARIANT_LABELS=(
  [vanilla]="Vanilla (No Root)"
  [ksu-next]="KernelSU-Next"
  [sukisu]="SukiSU-Ultra"
  [ksu-next+susfs]="KernelSU-Next with SUSFS"
  [sukisu-ultra+susfs]="SukiSU-Ultra with SUSFS"
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
    LD="${LD_BIN}"
    AR="${LLVM_BIN}/llvm-ar"
    NM="${LLVM_BIN}/llvm-nm"
    OBJCOPY="${LLVM_BIN}/llvm-objcopy"
    OBJDUMP="${LLVM_BIN}/llvm-objdump"
    READELF="${LLVM_BIN}/llvm-readelf"
    STRIP="${LLVM_BIN}/llvm-strip"
    CROSS_COMPILE="${CROSS_COMPILE}"
  )

  log "Generating defconfig (${DEFCONFIG})..."
  if [[ "$1" == *"susfs"* ]]; then
    scripts/config --file arch/arm64/configs/${DEFCONFIG} \
      -e KSU_SUSFS -e KSU_SUSFS_SUS_PATH -e KSU_SUSFS_SUS_MOUNT -e KSU_SUSFS_SUS_KSTAT \
      -e KSU_SUSFS_OPEN_REDIRECT -e KSU_SUSFS_TRY_UMOUNT \
      -e KSU_SUSFS_AUTO_ADD_SUS_KSU_DEFAULT_MOUNT -e KSU_SUSFS_AUTO_ADD_SUS_BIND_MOUNT \
      -e KSU_SUSFS_AUTO_ADD_TRY_UMOUNT_FOR_BIND_MOUNT -e KSU_SUSFS_SPOOF_UNAME \
      -e KSU_SUSFS_ENABLE_LOG -e KSU_SUSFS_HIDE_KSU_SUSFS_SYMBOLS \
      -e KSU_SUSFS_SPOOF_CMDLINE_OR_BOOTCONFIG -e KSU_SUSFS_SUS_MAP
  else
    scripts/config --file arch/arm64/configs/${DEFCONFIG} \
      -d KSU_SUSFS -d KSU_SUSFS_SUS_PATH -d KSU_SUSFS_SUS_MOUNT -d KSU_SUSFS_SUS_KSTAT \
      -d KSU_SUSFS_OPEN_REDIRECT -d KSU_SUSFS_TRY_UMOUNT \
      -d KSU_SUSFS_AUTO_ADD_SUS_KSU_DEFAULT_MOUNT -d KSU_SUSFS_AUTO_ADD_SUS_BIND_MOUNT \
      -d KSU_SUSFS_AUTO_ADD_TRY_UMOUNT_FOR_BIND_MOUNT -d KSU_SUSFS_SPOOF_UNAME \
      -d KSU_SUSFS_ENABLE_LOG -d KSU_SUSFS_HIDE_KSU_SUSFS_SYMBOLS \
      -d KSU_SUSFS_SPOOF_CMDLINE_OR_BOOTCONFIG -d KSU_SUSFS_SUS_MAP
  fi
  make "${MAKE_FLAGS[@]}" "${DEFCONFIG}"

  log "Compiling kernel (${JOBS} threads)..."
  local start_time=$SECONDS
  make "${MAKE_FLAGS[@]}" Image.gz-dtb
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

  log "Restoring device-specific anykernel.sh..."
  cp "${KERNEL_DIR}/anykernel-earth.sh" "${AK3_DIR}/anykernel.sh"

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
    ksu-next|sukisu|ksu-next+susfs|sukisu-ultra+susfs)
      local src="${VARIANT_DIRS[$variant]}"
      [[ -d "${KERNEL_DIR}/${src}/kernel" ]] || \
        err "'${src}/kernel' subdir missing — did submodules initialise?"
      
      # Determine branch/tag to check out
      local target_ref=""
      case "$variant" in
        ksu-next) target_ref="v3.2.0-legacy" ;;
        sukisu) target_ref="main" ;;
        ksu-next+susfs) target_ref="v3.2.0-legacy" ;;
        sukisu-ultra+susfs) target_ref="builtin" ;;
      esac
      
      log "Checking out ${target_ref} in ${src}..."
      # Make sure we have the reference (fetch if needed)
      git -C "${KERNEL_DIR}/${src}" fetch origin "${target_ref}:${target_ref}" --tags 2>/dev/null || \
      git -C "${KERNEL_DIR}/${src}" fetch origin "${target_ref}" --tags 2>/dev/null || true
      git -C "${KERNEL_DIR}/${src}" reset --hard HEAD 2>/dev/null || true
      git -C "${KERNEL_DIR}/${src}" clean -fd 2>/dev/null || true
      git -C "${KERNEL_DIR}/${src}" checkout -q "${target_ref}"
      
      if [[ "$variant" == "ksu-next+susfs" || "$variant" == "sukisu-ultra+susfs" ]]; then
        log "Injecting SUSFS v1.5.5 support into ${src} ${target_ref} branch..."
        
        # 1. Add #include <linux/susfs.h> and call susfs_try_umount(new_uid) in setuid_hook.c
        local setuid_hook="${KERNEL_DIR}/${src}/kernel/setuid_hook.c"
        if [[ ! -f "$setuid_hook" ]]; then
            # In legacy branches, it might be in root kernel/ directory or hook/
            if [[ -f "${KERNEL_DIR}/${src}/kernel/hook/setuid_hook.c" ]]; then
                setuid_hook="${KERNEL_DIR}/${src}/kernel/hook/setuid_hook.c"
            fi
        fi
        
        python3 -c '
import sys
filepath = sys.argv[1]
with open(filepath, "r") as f:
    content = f.read()

# Add include if not exists
if "#include <linux/susfs.h>" not in content:
    content = content.replace("#include \"feature/kernel_umount.h\"", "#include \"feature/kernel_umount.h\"\n#ifdef CONFIG_KSU_SUSFS\n#include <linux/susfs.h>\n#endif")

# Add susfs_try_umount if not exists
if "susfs_try_umount(new_uid);" not in content:
    content = content.replace("ksu_handle_umount(old_uid, new_uid);", "#ifdef CONFIG_KSU_SUSFS\n    susfs_try_umount(new_uid);\n#endif\n    ksu_handle_umount(old_uid, new_uid);")

with open(filepath, "w") as f:
    f.write(content)
' "$setuid_hook"

        # 2. Add SUSFS_MAGIC handler into supercalls.c or supercall.c
        local supercalls="${KERNEL_DIR}/${src}/kernel/supercalls.c"
        if [[ ! -f "$supercalls" ]]; then
            if [[ -f "${KERNEL_DIR}/${src}/kernel/supercall/supercall.c" ]]; then
                supercalls="${KERNEL_DIR}/${src}/kernel/supercall/supercall.c"
            fi
        fi
        python3 -c '
import sys
filepath = sys.argv[1]
with open(filepath, "r") as f:
    content = f.read()

magic_block = """
#ifdef CONFIG_KSU_SUSFS
    if (magic2 == SUSFS_MAGIC && current_uid().val == 0) {
        switch(cmd) {
        case CMD_SUSFS_ADD_SUS_PATH:
            susfs_add_sus_path((void __user *)arg4);
            return 0;
        case CMD_SUSFS_ADD_SUS_MOUNT:
            susfs_add_sus_mount((void __user *)arg4);
            return 0;
        case CMD_SUSFS_ADD_SUS_KSTAT:
            susfs_add_sus_kstat((void __user *)arg4);
            return 0;
        case CMD_SUSFS_UPDATE_SUS_KSTAT:
            susfs_update_sus_kstat((void __user *)arg4);
            return 0;
        case CMD_SUSFS_ADD_SUS_KSTAT_STATICALLY:
            susfs_add_sus_kstat((void __user *)arg4);
            return 0;
        case CMD_SUSFS_ADD_TRY_UMOUNT:
            susfs_add_try_umount((void __user *)arg4);
            return 0;
        case CMD_SUSFS_SET_UNAME:
            susfs_set_uname((void __user *)arg4);
            return 0;
        case CMD_SUSFS_ENABLE_LOG:
            susfs_set_log(1);
            return 0;
        case CMD_SUSFS_SET_CMDLINE_OR_BOOTCONFIG:
            susfs_set_cmdline_or_bootconfig((void __user *)arg4);
            return 0;
        case CMD_SUSFS_ADD_OPEN_REDIRECT:
            susfs_add_open_redirect((void __user *)arg4);
            return 0;
        default:
            return 0;
        }
    }
#endif // #ifdef CONFIG_KSU_SUSFS
"""

if "SUSFS_MAGIC" not in content:
    # Add include and define SUSFS_MAGIC
    if "uapi/supercall.h" in content:
        content = content.replace("#include \"uapi/supercall.h\"", "#include \"uapi/supercall.h\"\n#ifdef CONFIG_KSU_SUSFS\n#include <linux/susfs.h>\n#endif\n#ifndef SUSFS_MAGIC\n#define SUSFS_MAGIC 0x53555346\n#endif")
    else:
        content = content.replace("#include \"ksu.h\"", "#include \"ksu.h\"\n#ifdef CONFIG_KSU_SUSFS\n#include <linux/susfs.h>\n#endif\n#ifndef SUSFS_MAGIC\n#define SUSFS_MAGIC 0x53555346\n#endif")

    if "u64 reply = (u64)*arg;" in content:
        magic_block = magic_block.replace("arg4", "*arg")

    # Insert magic_block before CHANGE_MANAGER_UID
    import re
    content = re.sub(r"([ \t]*)if \(magic2 == CHANGE_MANAGER_UID\) \{", magic_block + r"\n\1if (magic2 == CHANGE_MANAGER_UID) {", content)

with open(filepath, "w") as f:
    f.write(content)
' "$supercalls"
      fi

      # 3. Add selinux domain functions
      local selinux_c="${KERNEL_DIR}/${src}/kernel/selinux/selinux.c"
      if [[ -f "$selinux_c" ]]; then
          python3 -c '
import sys
filepath = sys.argv[1]
with open(filepath, "r") as f:
    content = f.read()

selinux_patch = """
#ifdef CONFIG_KSU_SUSFS
#define KERNEL_INIT_DOMAIN "u:r:init:s0"
#define KERNEL_ZYGOTE_DOMAIN "u:r:zygote:s0"
#define KERNEL_PRIV_APP_DOMAIN "u:r:priv_app:s0:c512,c768"

u32 susfs_ksu_sid __read_mostly = 0;
u32 susfs_init_sid __read_mostly = 0;
u32 susfs_zygote_sid __read_mostly = 0;
u32 susfs_priv_app_sid __read_mostly = 0;

static inline void susfs_set_sid(const char *secctx_name, u32 *out_sid)
{
    int err;
    if (!secctx_name || !out_sid) return;
    err = security_secctx_to_secid(secctx_name, strlen(secctx_name), out_sid);
    if (err) return;
}

bool susfs_is_current_zygote_domain(void) {
    return unlikely(current_sid() == susfs_zygote_sid);
}

bool susfs_is_current_ksu_domain(void) {
    return unlikely(current_sid() == susfs_ksu_sid);
}

bool susfs_is_current_init_domain(void) {
    return unlikely(current_sid() == susfs_init_sid);
}

void susfs_set_batch_sid(void)
{
    susfs_set_sid(KERNEL_ZYGOTE_DOMAIN, &susfs_zygote_sid);
    susfs_set_sid(KERNEL_SU_CONTEXT, &susfs_ksu_sid);
    susfs_set_sid(KERNEL_INIT_DOMAIN, &susfs_init_sid);
    susfs_set_sid(KERNEL_PRIV_APP_DOMAIN, &susfs_priv_app_sid);
}
#endif // CONFIG_KSU_SUSFS
"""
if "susfs_is_current_ksu_domain" not in content:
    content += "\n" + selinux_patch
    with open(filepath, "w") as f:
        f.write(content)
' "$selinux_c"
      fi

      # 4. Call susfs_set_batch_sid in init.c
      local init_c="${KERNEL_DIR}/${src}/kernel/core/init.c"
      if [[ -f "$init_c" ]]; then
          python3 -c '
import sys, re
filepath = sys.argv[1]
with open(filepath, "r") as f:
    content = f.read()

if "susfs_set_batch_sid" not in content:
    if "#include <linux/susfs.h>" not in content:
        content = "#include <linux/susfs.h>\n" + content
    content = re.sub(r"(ksu_core_init\([^)]*\)\s*\{)", r"\1\n#ifdef CONFIG_KSU_SUSFS\n    susfs_set_batch_sid();\n#endif", content)
    with open(filepath, "w") as f:
        f.write(content)
' "$init_c"
      fi

      # 5. Define ksu_try_umount in kernel_umount.c
      local umount_c="${KERNEL_DIR}/${src}/kernel/feature/kernel_umount.c"
      if [[ -f "$umount_c" ]]; then
          python3 -c '
import sys
filepath = sys.argv[1]
with open(filepath, "r") as f:
    content = f.read()

umount_patch = """
#ifdef CONFIG_KSU_SUSFS_SUS_MOUNT
void ksu_try_umount(const char *mnt, bool check_mnt, int flags, uid_t uid) {
    try_umount(mnt, flags);
}
#endif
"""
if "ksu_try_umount" not in content:
    content += "\n" + umount_patch
    with open(filepath, "w") as f:
        f.write(content)
' "$umount_c"
      fi
      
      swap_ksu "$src"
      ksu_enable
      ;;
  esac
}

teardown_variant() {
  local variant="$1"
  [[ "$variant" == "vanilla" ]] && ksu_enable || true
  
  # Restore submodules to default branches
  if [[ "$variant" == "ksu-next" || "$variant" == "ksu-next+susfs" ]]; then
    log "Restoring KernelSU-Next to dev branch..."
    git -C "${KERNEL_DIR}/KernelSU-Next" reset --hard HEAD 2>/dev/null || true
    git -C "${KERNEL_DIR}/KernelSU-Next" clean -fd 2>/dev/null || true
    git -C "${KERNEL_DIR}/KernelSU-Next" checkout -q dev || true
  elif [[ "$variant" == "sukisu" || "$variant" == "sukisu-ultra+susfs" ]]; then
    log "Restoring SukiSU to main branch..."
    git -C "${KERNEL_DIR}/SukiSU" reset --hard HEAD 2>/dev/null || true
    git -C "${KERNEL_DIR}/SukiSU" clean -fd 2>/dev/null || true
    git -C "${KERNEL_DIR}/SukiSU" checkout -q main || true
  fi
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
    variants=(vanilla ksu-next sukisu ksu-next+susfs sukisu-ultra+susfs)
    log "No variant specified — building ALL variants"
  else
    for arg in "$@"; do
      case "$arg" in
        vanilla|ksu-next|sukisu|ksu-next+susfs|sukisu-ultra+susfs) variants+=("$arg") ;;
        *) err "Unknown variant '${arg}'. Valid: vanilla | ksu-next | sukisu | ksu-next+susfs | sukisu-ultra+susfs" ;;
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
  for v in "${built[@]:-}"; do
    [[ -n "$v" ]] && echo -e "  ${GREEN}✓${RESET} ${VARIANT_LABELS[$v]}"
  done
  for v in "${failed[@]:-}"; do
    [[ -n "$v" ]] && echo -e "  ${RED}✗${RESET} ${VARIANT_LABELS[$v]}"
  done

  echo ""
  if [[ ${#built[@]} -gt 0 ]]; then
    echo -e "  Output: ${BOLD}${RELEASES_DIR}/${RESET}"
    ls -lh "${RELEASES_DIR}"/kernel-earth-*-"${DATE}".zip 2>/dev/null \
      | awk '{print "  📦 "$NF" ("$5")"}' || true
  fi

  [[ ${#failed[@]} -eq 0 ]] || exit 1
}

main "$@"
