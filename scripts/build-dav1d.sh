#!/usr/bin/env bash
# dav1d, the AV1 decoder of phreox-media, as a static library with a pkg-config file, for the builds that have no package of it (Windows, macOS). The crate that uses
# it (dav1d-sys) asks pkg-config for it; with SYSTEM_DEPS_DAV1D_LINK=static the decoder is part of the executable, so the app needs no library next to it.
#
#   scripts/build-dav1d.sh <prefix>      then:  PKG_CONFIG_PATH=<prefix>/lib/pkgconfig  SYSTEM_DEPS_DAV1D_LINK=static
#
# Needs meson, ninja and a C compiler (on Windows the one of Visual Studio, in the environment of its developer prompt); on x86 also nasm.
set -euo pipefail

VERSION="1.5.1"
SHA256="401813f1f89fa8fd4295805aa5284d9aed9bc7fc1fdbe554af4292f64cbabe21"
URL="https://downloads.videolan.org/pub/videolan/dav1d/${VERSION}/dav1d-${VERSION}.tar.xz"

prefix="${1:?usage: build-dav1d.sh <prefix>}"
work="$(mktemp -d)"
python="$(command -v python3 || command -v python)"

# A path that the compiler of the platform understands (C:/... on Windows, the same everywhere else).
native() { if command -v cygpath >/dev/null; then cygpath -m "$1"; else echo "$1"; fi; }

# The server drops a connection now and then, and a file that is not the pinned one is refused.
curl -fsSL --retry 6 --retry-delay 5 --retry-all-errors --retry-connrefused --connect-timeout 20 -o "$work/dav1d.tar.xz" "$URL"
echo "$SHA256  $work/dav1d.tar.xz" | (sha256sum -c - || shasum -a 256 -c -)

# Python unpacks the .xz on every platform; the tar of a Windows runner may not.
"$python" -c "import sys, tarfile; tarfile.open(sys.argv[1]).extractall(sys.argv[2])" "$(native "$work/dav1d.tar.xz")" "$(native "$work")"

cd "$work/dav1d-$VERSION"
# On Windows the library is built with the static C runtime, the same one the app is linked with (its .cargo config says +crt-static).
# Without it meson uses the DLL runtime and the link of the executable fails (unresolved __imp__aligned_malloc).
vscrt=()
if command -v cygpath >/dev/null; then vscrt=(-Db_vscrt=mt); fi
meson setup build --prefix "$(native "$prefix")" --libdir lib --buildtype release --default-library static "${vscrt[@]}" \
    -Denable_tools=false -Denable_tests=false -Denable_examples=false -Denable_docs=false
ninja -C build install

echo "dav1d $VERSION in $prefix"
ls "$prefix/lib" "$prefix/lib/pkgconfig"
