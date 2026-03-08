#!/usr/bin/env bash
set -euo pipefail

# Cross-compile Python 3.13.12 for Android — supports multiple arches & API levels
# Applies patches from patches/ directory
# Designed for GitHub Actions (macOS runner) + NDK r29

echo "Building Python ${TERMUX_PKG_VERSION:-3.13.12} for Android"

# Required/optional env vars
: "${ANDROID_NDK_HOME:?Missing ANDROID_NDK_HOME}"
: "${API_LEVEL:=35}"                    # Any level ≥24
: "${TARGET_ARCH:=aarch64}"             # aarch64 | arm | x86_64 | x86
: "${INSTALL_PREFIX:=$(pwd)/python-install}"

# Map arch to NDK host triple & sysroot lib dir
case "$TARGET_ARCH" in
  aarch64)
    HOST_PLATFORM="aarch64-linux-android"
    LIB_DIR="aarch64-linux-android"
    ;;
  arm)
    HOST_PLATFORM="armv7a-linux-androideabi"
    LIB_DIR="arm-linux-androideabi"
    ;;
  x86_64)
    HOST_PLATFORM="x86_64-linux-android"
    LIB_DIR="x86_64-linux-android"
    ;;
  x86)
    HOST_PLATFORM="i686-linux-android"
    LIB_DIR="i686-linux-android"
    ;;
  *)
    echo "Unsupported TARGET_ARCH: $TARGET_ARCH (use: aarch64, arm, x86_64, x86)"
    exit 1
    ;;
esac

# Toolchain setup
TOOLCHAIN_BIN="${ANDROID_NDK_HOME}/toolchains/llvm/prebuilt/darwin-x86_64/bin"
export PATH="${TOOLCHAIN_BIN}:${PATH}"

export CC="${HOST_PLATFORM}${API_LEVEL}-clang"
export CXX="${HOST_PLATFORM}${API_LEVEL}-clang++"
export AR="llvm-ar"
export RANLIB="llvm-ranlib"
export STRIP="${HOST_PLATFORM}-strip"
export LD="${HOST_PLATFORM}-ld"

export CFLAGS="-fPIC -fPIE -DANDROID --sysroot=${ANDROID_NDK_HOME}/sysroot"
export CXXFLAGS="$CFLAGS"
export LDFLAGS="-pie -L${ANDROID_NDK_HOME}/sysroot/usr/lib/${LIB_DIR}"

# Fake Termux prefix for patches
export TERMUX_PREFIX="/data/data/com.termux/files/usr"
export TERMUX_PKG_API_LEVEL="${API_LEVEL}"

# Original-style configure args + cross-compile additions
CONFIGURE_ARGS=(
  "--host=${HOST_PLATFORM}"
  "--target=${HOST_PLATFORM}"
  "--prefix=${INSTALL_PREFIX}"
  "--libdir=${INSTALL_PREFIX}/lib"
  "--with-platlibdir=lib"
  "--enable-shared"
  "--with-system-ffi"
  "--with-system-expat"
  "--without-ensurepip"
  "ac_cv_file__dev_ptmx=yes"
  "ac_cv_file__dev_ptc=no"
  "ac_cv_func_wcsftime=no"
  "ac_cv_func_ftime=no"
  "ac_cv_func_faccessat=no"
  "ac_cv_func_linkat=no"
  "ac_cv_buggy_getaddrinfo=no"
  "ac_cv_little_endian_double=yes"
  "ac_cv_posix_semaphores_enabled=yes"
  "ac_cv_func_sem_open=yes"
  "ac_cv_func_sem_timedwait=yes"
  "ac_cv_func_sem_getvalue=yes"
  "ac_cv_func_sem_unlink=yes"
  "ac_cv_func_shm_open=yes"
  "ac_cv_func_shm_unlink=yes"
  "ac_cv_working_tzset=yes"
  "ac_cv_header_sys_xattr_h=no"
  "ac_cv_func_getgrent=yes"
  "ac_cv_have_long_long_format=yes"
)

SRC_DIR="$(pwd)/src"
BUILD_DIR="$(pwd)/build"
PATCHES_DIR="$(pwd)/patches"

mkdir -p "${SRC_DIR}" "${BUILD_DIR}" "${INSTALL_PREFIX}"

# Extract sources
tar -xf "Python-3.13.12.tar.xz" -C "${SRC_DIR}" --strip-components=1
tar -xf "python3-defaults-f358ab52bf2932ad55b1a72a29c9762169e6ac47.tar.gz" -C "${SRC_DIR}"
mv "${SRC_DIR}/python3-defaults-f358ab52bf2932ad55b1a72a29c9762169e6ac47" "${SRC_DIR}/debpython"

# Apply patches (like Termux auto-apply)
if [[ -d "${PATCHES_DIR}" && -n "$(ls -A "${PATCHES_DIR}"/*.patch "${PATCHES_DIR}"/*.diff 2>/dev/null)" ]]; then
  echo "Applying patches from ${PATCHES_DIR}/ (alphanumeric order)"
  cd "${SRC_DIR}" || exit 1
  for patch in "${PATCHES_DIR}"/*.patch "${PATCHES_DIR}"/*.diff; do
    if [[ -f "$patch" ]]; then
      echo "  → $(basename "$patch")"
      if ! patch -p1 --no-backup-if-mismatch < "$patch"; then
        echo "Patch failed: $patch"
        exit 1
      fi
    fi
  done
  cd - >/dev/null || exit 1
else
  echo "No patches found — skipping patch step"
fi

cd "${BUILD_DIR}" || exit 1

echo "Configuring for ${TARGET_ARCH} (API ${API_LEVEL})..."
"${SRC_DIR}/configure" "${CONFIGURE_ARGS[@]}" \
  CPPFLAGS="${CPPFLAGS:-}" LDFLAGS="${LDFLAGS}"

echo "Building (using $(sysctl -n hw.ncpu) cores)..."
make -j$(sysctl -n hw.ncpu)

echo "Installing..."
make install

# Verification
if [[ -x "${INSTALL_PREFIX}/bin/python3.13" ]]; then
  echo "Success! Python version:"
  "${INSTALL_PREFIX}/bin/python3.13" --version
  file "${INSTALL_PREFIX}/bin/python3.13"   # Show architecture
else
  echo "Build failed — python3.13 not found"
  exit 1
fi

echo "Done. Installed to: ${INSTALL_PREFIX}"
