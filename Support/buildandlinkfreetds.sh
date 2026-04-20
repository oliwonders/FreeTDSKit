#!/bin/bash
set -euo pipefail

MACOSX_DEPLOYMENT_TARGET="15.0"
OPENSSL_VERSION="3.3.3"
FREETDS_VERSION="1.5.17"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUILD_DIR="$SCRIPT_DIR/build"
OPENSSL_PREFIX="$BUILD_DIR/static-openssl"
FREETDS_PREFIX="$BUILD_DIR/static-freetds"
DEST_DIR="$SCRIPT_DIR/../Sources/CFreeTDS"

ARCH=$(uname -m)
if [ "$ARCH" = "arm64" ]; then
    OPENSSL_TARGET="darwin64-arm64-cc"
else
    OPENSSL_TARGET="darwin64-x86_64-cc"
fi

export MACOSX_DEPLOYMENT_TARGET
export CFLAGS="-mmacosx-version-min=$MACOSX_DEPLOYMENT_TARGET"
export LDFLAGS="-mmacosx-version-min=$MACOSX_DEPLOYMENT_TARGET"

mkdir -p "$BUILD_DIR"

# --- Build OpenSSL ---
echo "==> Building OpenSSL $OPENSSL_VERSION for macOS $MACOSX_DEPLOYMENT_TARGET ($ARCH)"
cd "$BUILD_DIR"

if [ ! -f "openssl-${OPENSSL_VERSION}.tar.gz" ]; then
    curl -LO "https://www.openssl.org/source/openssl-${OPENSSL_VERSION}.tar.gz"
fi
rm -rf "openssl-${OPENSSL_VERSION}"
tar xzf "openssl-${OPENSSL_VERSION}.tar.gz"
cd "openssl-${OPENSSL_VERSION}"

./Configure "$OPENSSL_TARGET" \
    --prefix="$OPENSSL_PREFIX" \
    no-shared \
    no-tests

make -j"$(sysctl -n hw.logicalcpu)"
make install_sw

echo "✅ OpenSSL built"

# --- Build FreeTDS ---
echo "==> Building FreeTDS $FREETDS_VERSION for macOS $MACOSX_DEPLOYMENT_TARGET ($ARCH)"
cd "$BUILD_DIR"

if [ ! -f "freetds-${FREETDS_VERSION}.tar.gz" ]; then
    curl -LO "ftp://ftp.freetds.org/pub/freetds/stable/freetds-${FREETDS_VERSION}.tar.gz"
fi
rm -rf "freetds-${FREETDS_VERSION}"
tar xzf "freetds-${FREETDS_VERSION}.tar.gz"
cd "freetds-${FREETDS_VERSION}"

export LDFLAGS="-mmacosx-version-min=$MACOSX_DEPLOYMENT_TARGET -L$OPENSSL_PREFIX/lib"
export CPPFLAGS="-I$OPENSSL_PREFIX/include"

./configure \
    --disable-shared \
    --enable-static \
    --with-openssl="$OPENSSL_PREFIX" \
    --prefix="$FREETDS_PREFIX"

make -j"$(sysctl -n hw.logicalcpu)"
make install

echo "✅ FreeTDS built"

# --- Copy to package ---
echo "==> Copying artifacts to Sources/CFreeTDS"

cp "$FREETDS_PREFIX/lib/libsybdb.a"    "$DEST_DIR/"
cp "$OPENSSL_PREFIX/lib/libcrypto.a"   "$DEST_DIR/"
cp "$OPENSSL_PREFIX/lib/libssl.a"      "$DEST_DIR/"

echo "✅ Copied libsybdb.a, libcrypto.a, libssl.a"
echo ""
echo "Verifying deployment targets:"
for lib in libsybdb.a libcrypto.a libssl.a; do
    echo -n "  $lib: "
    # Extract one object and check its version
    tmpdir=$(mktemp -d)
    ar -x "$DEST_DIR/$lib" --output "$tmpdir" 2>/dev/null || true
    first_obj=$(ls "$tmpdir"/*.o 2>/dev/null | head -1)
    if [ -n "$first_obj" ]; then
        vtool -show-build "$first_obj" 2>/dev/null | grep -E "minos|platform" | tr '\n' ' ' || echo "(unable to read)"
    fi
    echo ""
    rm -rf "$tmpdir"
done
