#!/bin/bash
# Build OpenSSL and FreeTDS as static, universal (arm64 + x86_64) macOS
# libraries and package them as Frameworks/FreeTDS.xcframework, which
# Package.swift consumes as a binary target.
#
# The binary target is what lets FreeTDSKit be used as a remote SwiftPM
# dependency: SwiftPM refuses unsafeFlags in any package that isn't the root,
# so the archives can't be linked by path from the manifest.
set -euo pipefail

MACOSX_DEPLOYMENT_TARGET="15.0"
OPENSSL_VERSION="3.5.8"
FREETDS_VERSION="1.5.19"
ARCHS=(arm64 x86_64)

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PACKAGE_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
BUILD_DIR="$SCRIPT_DIR/build"
UNIVERSAL_DIR="$BUILD_DIR/universal"
XCFRAMEWORK="$PACKAGE_DIR/Frameworks/FreeTDS.xcframework"
NCPU="$(sysctl -n hw.logicalcpu)"

export MACOSX_DEPLOYMENT_TARGET

mkdir -p "$BUILD_DIR"
cd "$BUILD_DIR"

if [ ! -f "openssl-${OPENSSL_VERSION}.tar.gz" ]; then
    curl -LO "https://www.openssl.org/source/openssl-${OPENSSL_VERSION}.tar.gz"
fi
if [ ! -f "freetds-${FREETDS_VERSION}.tar.gz" ]; then
    curl -LO "https://www.freetds.org/files/stable/freetds-${FREETDS_VERSION}.tar.gz"
fi

build_arch() {
    local arch="$1"
    local openssl_target host
    case "$arch" in
        arm64)  openssl_target="darwin64-arm64-cc";  host="aarch64-apple-darwin" ;;
        x86_64) openssl_target="darwin64-x86_64-cc"; host="x86_64-apple-darwin" ;;
    esac

    local src_dir="$BUILD_DIR/src-$arch"
    local openssl_prefix="$BUILD_DIR/static-openssl-$arch"
    local freetds_prefix="$BUILD_DIR/static-freetds-$arch"
    local cflags="-arch $arch -mmacosx-version-min=$MACOSX_DEPLOYMENT_TARGET"

    rm -rf "$src_dir" "$openssl_prefix" "$freetds_prefix"
    mkdir -p "$src_dir"

    echo "==> Building OpenSSL $OPENSSL_VERSION ($arch, macOS $MACOSX_DEPLOYMENT_TARGET)"
    tar xzf "$BUILD_DIR/openssl-${OPENSSL_VERSION}.tar.gz" -C "$src_dir"
    (
        cd "$src_dir/openssl-${OPENSSL_VERSION}"
        CFLAGS="$cflags" ./Configure "$openssl_target" \
            --prefix="$openssl_prefix" \
            --libdir=lib \
            no-shared \
            no-tests
        make -j"$NCPU"
        make install_sw
    )

    # FreeTDS is autoconf: --host tells configure this may be a cross build,
    # so it doesn't try to run x86_64 test programs on an arm64 machine.
    echo "==> Building FreeTDS $FREETDS_VERSION ($arch, macOS $MACOSX_DEPLOYMENT_TARGET)"
    tar xzf "$BUILD_DIR/freetds-${FREETDS_VERSION}.tar.gz" -C "$src_dir"
    (
        cd "$src_dir/freetds-${FREETDS_VERSION}"
        CC="clang" \
        CFLAGS="$cflags" \
        CPPFLAGS="-I$openssl_prefix/include" \
        LDFLAGS="$cflags -L$openssl_prefix/lib" \
        ./configure \
            --host="$host" \
            --disable-shared \
            --enable-static \
            --with-openssl="$openssl_prefix" \
            --prefix="$freetds_prefix"
        make -j"$NCPU"
        make install
    )

    # One archive per arch holding FreeTDS and the OpenSSL it was built
    # against, so the xcframework is a single library and the three can never
    # drift apart.
    libtool -static -no_warning_for_no_symbols -o "$BUILD_DIR/libfreetds-$arch.a" \
        "$freetds_prefix/lib/libsybdb.a" \
        "$openssl_prefix/lib/libssl.a" \
        "$openssl_prefix/lib/libcrypto.a"
}

for arch in "${ARCHS[@]}"; do
    build_arch "$arch"
done

echo "==> Creating universal archive"
rm -rf "$UNIVERSAL_DIR"
mkdir -p "$UNIVERSAL_DIR/Headers"
thin_archives=()
for arch in "${ARCHS[@]}"; do
    thin_archives+=("$BUILD_DIR/libfreetds-$arch.a")
done
lipo -create "${thin_archives[@]}" -output "$UNIVERSAL_DIR/libfreetds.a"

# Headers are identical across arches; take them from the first build.
cp "$BUILD_DIR/static-freetds-${ARCHS[0]}/include/"*.h "$UNIVERSAL_DIR/Headers/"
# No `link` directive: the binary target links the archive itself, and an
# autolink of "sybdb" would let the linker go searching (and find Homebrew's).
cat > "$UNIVERSAL_DIR/Headers/module.modulemap" <<'EOF'
module CSybDB {
    header "sybdb.h"
    export *
}
EOF

echo "==> Creating $XCFRAMEWORK"
rm -rf "$XCFRAMEWORK"
mkdir -p "$(dirname "$XCFRAMEWORK")"
xcodebuild -create-xcframework \
    -library "$UNIVERSAL_DIR/libfreetds.a" \
    -headers "$UNIVERSAL_DIR/Headers" \
    -output "$XCFRAMEWORK"

echo ""
echo "Verifying slices and deployment targets:"
lib="$(find "$XCFRAMEWORK" -name 'libfreetds.a' -print -quit)"
lipo -info "$lib"
for arch in "${ARCHS[@]}"; do
    tmpdir=$(mktemp -d)
    lipo -thin "$arch" "$lib" -output "$tmpdir/thin.a"
    # BSD ar (the one on macOS) has no --output, so extract from inside tmpdir.
    (cd "$tmpdir" && ar -x thin.a) 2>/dev/null || true
    # -print -quit rather than a pipe to head: piping into head kills find with
    # SIGPIPE on a large archive, which pipefail turns into a script failure.
    first_obj=$(find "$tmpdir" -maxdepth 1 -name '*.o' -print -quit)
    echo -n "  $arch: "
    if [ -n "$first_obj" ]; then
        vtool -show-build "$first_obj" 2>/dev/null | grep -E "minos|platform" | tr -s ' \n' ' ' || printf "(unable to read)"
    else
        printf "(no object files extracted)"
    fi
    echo ""
    rm -rf "$tmpdir"
done
echo "✅ FreeTDS $FREETDS_VERSION + OpenSSL $OPENSSL_VERSION -> Frameworks/FreeTDS.xcframework"
