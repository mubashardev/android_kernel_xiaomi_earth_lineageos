# 🐉 Xiaomi Earth Multi-Variant Kernel (MT6768 / 4.19)

A highly optimized and customizable kernel build system for **Redmi 12C / Poco C55 (codename: `earth`)**, based on **LineageOS 23.2** (Android 15) source.

This repository features automated multi-variant building, integrating cutting-edge root and security solutions like **KernelSU-Next**, **SukiSU-Ultra**, and **SUSFS**.

---

## 🚀 Key Features

* **Multi-Variant Builds:** Compile vanilla, KernelSU-Next, SukiSU-Ultra, or SUSFS-patched variants with a single command.
* **SUSFS Integration:** Complete automated patching of KernelSU-Next and SukiSU-Ultra with SUSFS v1.5.5 (cloaking paths, spoofing uname, try-umount, open-redirect, hiding symbols, etc.).
* **AnyKernel3 Ramdisk Modding:** Automatically packages the compiled kernel `Image.gz-dtb` into flashable ZIPs tailored for `earth` devices.
* **OS-Aware Build Toolchain:** Built-in support for both **Linux (Ubuntu)** and **macOS (Darwin)** build environments.
* **CI/CD Pipeline:** Fully configured GitHub Actions workflow for automated matrix building and publication of GitHub releases.

---

## 📦 Build Variants

| Variant | Root / Hiding Solution | Build Command | Description |
|---|---|---|---|
| **Vanilla** | None | `./build.sh vanilla` | Clean stock-like build (No Root / systemless mods) |
| **KSU-Next** | KernelSU-Next | `./build.sh ksu-next` | KernelSU-Next root |
| **SukiSU** | SukiSU-Ultra | `./build.sh sukisu` | SukiSU-Ultra root |
| **KSU-Next + SUSFS** | KernelSU-Next + SUSFS v1.5.5 | `./build.sh ksu-next+susfs` | KernelSU-Next with full SUSFS cloaking |
| **SukiSU + SUSFS** | SukiSU-Ultra + SUSFS v1.5.5 | `./build.sh sukisu-ultra+susfs` | SukiSU-Ultra with full SUSFS cloaking |

---

## 🛠️ Local Build Instructions

### Prerequisites

#### macOS (Darwin)
Ensure you have Homebrew installed, then run:
```bash
brew install llvm make zip
```
The build script automatically detects macOS and locates the Homebrew LLVM/Clang toolchain.

#### Linux (Ubuntu/Debian)
Install the required build dependencies:
```bash
sudo apt-get update
sudo apt-get install -y clang-17 lld-17 llvm-17 gcc-aarch64-linux-gnu bc flex bison make libssl-dev libelf-dev libyaml-dev zip unzip python3
```

### Cloning the Repository
Since this repository relies on submodules for KernelSU-Next and SukiSU-Ultra, ensure you clone recursively:
```bash
git clone --recursive <repository-url>
# Or if already cloned:
git submodule update --init --recursive
```

### Running the Build
To compile the kernel and generate flashable ZIPs, execute `build.sh`:

```bash
# Build ALL variants
./build.sh

# Build a specific variant (e.g. KernelSU-Next with SUSFS)
./build.sh ksu-next+susfs

# Build multiple specific variants
./build.sh vanilla ksu-next+susfs
```

All build outputs (flashable ZIPs) are saved in the `releases/` directory.

---

## 🔗 Submodule Management
The build system manages the kernel source by swapping the `KernelSU` directory link to point to either the `KernelSU-Next` or `SukiSU` submodules depending on the target variant.

* **KernelSU-Next:** Linked to the `KernelSU-Next/` directory (checkout: `v3.2.0-legacy` for builds).
* **SukiSU-Ultra:** Linked to the `SukiSU/` directory (checkout: `main` or `builtin` depending on the variant).

The build script takes care of checking out the correct commits/branches, applying the necessary patches (for SUSFS variants), and restoring the repository state after compilation.

---

## 🤖 GitHub Actions Workflow
The repository includes a GitHub Actions configuration located in `.github/workflows/build.yml.bak` (can be renamed to `.github/workflows/build.yml` to activate).

* **Matrix Build:** Builds all 5 variants in parallel.
* **Auto-Release:** When pushing to the main branch (`lineage-23.2`), it automatically packages, tags, and drafts a GitHub Release containing all five variant ZIPs and dynamically generated release notes.

---

## ⚠️ Flash Instructions

### Method 1: ADB Sideload via LineageOS Recovery (Recommended)

1. Reboot your device into LineageOS Recovery:
   ```bash
   adb reboot recovery
   ```
2. Navigate to **Apply Update** > **Apply from ADB**.
3. Connect your phone to your PC/Mac and run:
   ```bash
   adb sideload KernelSU-Next-Earth.zip
   ```
4. *Note:* You will encounter a "Signature verification failed" warning. This is completely normal for unofficial zips. Select **Yes / Continue** to proceed with the installation.
5. Reboot to the system.

### Method 2: Standard Custom Recovery (TWRP / OrangeFox)

1. Reboot your device into your custom recovery.
2. Locate the downloaded `KernelSU-Next-Earth.zip` file.
3. Swipe to flash.
4. Reboot to the system.
