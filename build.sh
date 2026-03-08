#!/usr/bin/env bash
set -euo pipefail

# ────────────────────────────────────────────────────────────────────────────────
# Cross-compile Python 3.13.12 for Android (aarch64 only) using NDK r29 + API 35
# Designed for GitHub Actions on macOS runner
# ────────────────────────────────────────────────────────────────────────────────

echo "Starting Python cross-build for Android aarch64 (API 35)"

# Required environment variables (set by workflow)
: "${ANDROID_NDK_HOME:?ANDROID_NDK_HOME is required}"
: "${ANDROID_SDK_ROOT:?ANDROID_SDK_ROOT is required}"
: "${API_LEVEL:=35}"
: "${TARGET_ARCH:=aarch64}"
: "${INSTALL_PREFIX:=$(pwd)/python-install}"

if [[ "$TARGET_ARCH" != "aarch64" ]]; then
  echo "Error: This script is configured for aarch64 only"
  exit 1
fi

HOST_PLATFORM="aarch64-linux-android"

# Toolchain setup (NDK r29 is already installed via sdkmanager)
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
export LDFLAGS="-pie -L${ANDROID_NDK_HOME}/sysroot/usr/lib/aarch64-linux-android"

# Fake Termux-like prefix for path substitutions in patches
export TERMUX_PREFIX="/data/data/com.termux/files/usr"
export TERMUX_PKG_API_LEVEL="${API_LEVEL}"
export TERMUX_STANDALONE_TOOLCHAIN="${ANDROID_NDK_HOME}"

# Configure flags (Android-specific + cross-compile)
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

# Source preparation (assume sources are downloaded in workflow)
SRC_DIR="$(pwd)/src"
BUILD_DIR="$(pwd)/build"

mkdir -p "${SRC_DIR}" "${BUILD_DIR}"

# If sources not already extracted:
if [[ ! -d "${SRC_DIR}/Python-${TERMUX_PKG_VERSION}" ]]; then
  tar -xf "Python-${TERMUX_PKG_VERSION}.tar.xz" -C "${SRC_DIR}"
  tar -xf "python3-defaults-${_DEBPYTHON_COMMIT}.tar.gz" -C "${SRC_DIR}"
  mv "${SRC_DIR}/python3-defaults-${_DEBPYTHON_COMMIT}" "${SRC_DIR}/debpython"
fi

cd "${BUILD_DIR}" || exit 1

echo "Configuring Python ..."
"${SRC_DIR}/Python-${TERMUX_PKG_VERSION}/configure" "${CONFIGURE_ARGS[@]}" \
  CPPFLAGS="${CPPFLAGS:-}" LDFLAGS="${LDFLAGS}"

echo "Building ..."
make -j$(sysctl -n hw.ncpu)

echo "Installing ..."
make install

# Basic verification
if [[ -x "${INSTALL_PREFIX}/bin/python3.13" ]]; then
  echo "Build successful!"
  "${INSTALL_PREFIX}/bin/python3.13" --version
else
  echo "Build failed: python3.13 binary not found"
  exit 1
fi

echo "Python installed to: ${INSTALL_PREFIX}"
ls -la "${INSTALL_PREFIX}/bin"
