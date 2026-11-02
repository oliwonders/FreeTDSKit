#!/bin/bash
# Build OpenSSL and FreeTDS for macOS (arm64 + x86_64) as one dynamic
# framework, FreeTDS.framework, packaged as Frameworks/FreeTDS.xcframework,
# which Package.swift consumes as a binary target.
#
# Dynamic, so an app embeds FreeTDS as a separate library its users could
# replace with their own build, as the LGPL asks -- static linking would
# oblige every app to offer its object files for relinking. OpenSSL (Apache
# 2.0) is linked into the framework statically.
#
# The binary target is what lets FreeTDSKit be used as a remote SwiftPM
# dependency: SwiftPM refuses unsafeFlags in any package that isn't the root,
# so the libraries can't be linked by path from the manifest.
set -euo pipefail

MACOSX_DEPLOYMENT_TARGET="15.0"
OPENSSL_VERSION="3.5.9"
FREETDS_VERSION="1.5.19"
# SHA-256 of each source tarball. Update alongside the version, from a source
# other than the download itself: openssl.org/source/<tarball>.sha256 (also on
# the GitHub release), and freetds.org/files/stable/<tarball>.md5 cross-checked
# against a second download.
OPENSSL_SHA256="603f5602e2eef00d77fbd429d34dcd5822bb301757a1bc9cdb24c670f1eb859a"
FREETDS_SHA256="ff70d0c8ae8dd23e7b1314274d6e9d30b479998415760b3fa656754b737c2bd6"
ARCHS=(arm64 x86_64)

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PACKAGE_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
BUILD_DIR="$SCRIPT_DIR/build"
UNIVERSAL_DIR="$BUILD_DIR/universal"
XCFRAMEWORK="$PACKAGE_DIR/Frameworks/FreeTDS.xcframework"
FRAMEWORK="$UNIVERSAL_DIR/FreeTDS.framework"
PRIVACY_MANIFEST="$SCRIPT_DIR/FreeTDS-PrivacyInfo.xcprivacy"
PATCH_DIR="$SCRIPT_DIR/patches"
# Where the libraries *think* they are installed. FreeTDS and OpenSSL compile
# their prefix into the binary as the place to look for freetds.conf,
# openssl.cnf and CA certificates, so a prefix under this checkout would ship
# your home folder path inside every app and point those lookups at it. The
# real install goes to a per-arch staging directory via DESTDIR.
INSTALL_PREFIX="/usr/local/freetdskit"
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

# These archives become the TLS stack of every app that uses FreeTDSKit; refuse
# to build from anything but the exact source that was reviewed.
verify_sha256() {
    local file="$1" expected="$2" actual
    actual="$(shasum -a 256 "$file" | cut -d' ' -f1)"
    if [ "$actual" != "$expected" ]; then
        echo "❌ $file: SHA-256 $actual, expected $expected"
        exit 1
    fi
}
verify_sha256 "openssl-${OPENSSL_VERSION}.tar.gz" "$OPENSSL_SHA256"
verify_sha256 "freetds-${FREETDS_VERSION}.tar.gz" "$FREETDS_SHA256"

build_arch() {
    local arch="$1"
    local openssl_target host
    case "$arch" in
        arm64)  openssl_target="darwin64-arm64-cc";  host="aarch64-apple-darwin" ;;
        x86_64) openssl_target="darwin64-x86_64-cc"; host="x86_64-apple-darwin" ;;
    esac

    local src_dir="$BUILD_DIR/src-$arch"
    local stage_dir="$BUILD_DIR/stage-$arch"
    local staged="$stage_dir$INSTALL_PREFIX"
    local cflags="-arch $arch -mmacosx-version-min=$MACOSX_DEPLOYMENT_TARGET"

    rm -rf "$src_dir" "$stage_dir"
    mkdir -p "$src_dir"

    echo "==> Building OpenSSL $OPENSSL_VERSION ($arch, macOS $MACOSX_DEPLOYMENT_TARGET)"
    tar xzf "$BUILD_DIR/openssl-${OPENSSL_VERSION}.tar.gz" -C "$src_dir"
    (
        cd "$src_dir/openssl-${OPENSSL_VERSION}"
        CFLAGS="$cflags" ./Configure "$openssl_target" \
            --prefix="$INSTALL_PREFIX" \
            --openssldir="$INSTALL_PREFIX/ssl" \
            --libdir=lib \
            no-shared \
            no-tests
        make -j"$NCPU"
        make install_sw DESTDIR="$stage_dir"
    )

    # FreeTDS is autoconf: --host tells configure this may be a cross build,
    # so it doesn't try to run x86_64 test programs on an arm64 machine.
    echo "==> Building FreeTDS $FREETDS_VERSION ($arch, macOS $MACOSX_DEPLOYMENT_TARGET)"
    tar xzf "$BUILD_DIR/freetds-${FREETDS_VERSION}.tar.gz" -C "$src_dir"
    (
        cd "$src_dir/freetds-${FREETDS_VERSION}"
        # FreeTDSKit's changes to FreeTDS; see Support/patches/README.md.
        for patch_file in "$PATCH_DIR"/freetds-*.patch; do
            echo "    applying $(basename "$patch_file")"
            patch -p1 --forward --batch < "$patch_file"
        done
        CC="clang" \
        CFLAGS="$cflags" \
        CPPFLAGS="-I$staged/include" \
        LDFLAGS="$cflags -L$staged/lib" \
        ./configure \
            --host="$host" \
            --disable-shared \
            --enable-static \
            --with-openssl="$staged" \
            --prefix="$INSTALL_PREFIX"
        make -j"$NCPU"
        make install DESTDIR="$stage_dir"
    )

    # One dynamic library per arch holding FreeTDS and the OpenSSL it was
    # built against, so the three can never drift apart. -all_load keeps
    # every symbol: what's used is decided when an app links.
    clang -dynamiclib $cflags \
        -install_name "@rpath/FreeTDS.framework/Versions/A/FreeTDS" \
        -compatibility_version 1.0 -current_version "$FREETDS_VERSION" \
        -Wl,-all_load \
        "$staged/lib/libsybdb.a" \
        "$staged/lib/libssl.a" \
        "$staged/lib/libcrypto.a" \
        -liconv \
        -o "$BUILD_DIR/FreeTDS-$arch"
}

for arch in "${ARCHS[@]}"; do
    build_arch "$arch"
done

echo "==> Creating FreeTDS.framework"
rm -rf "$UNIVERSAL_DIR"
version_dir="$FRAMEWORK/Versions/A"
mkdir -p "$version_dir/Headers" "$version_dir/Modules" "$version_dir/Resources"
thin_libraries=()
for arch in "${ARCHS[@]}"; do
    thin_libraries+=("$BUILD_DIR/FreeTDS-$arch")
done
lipo -create "${thin_libraries[@]}" -output "$version_dir/FreeTDS"

# Headers are identical across arches; take them from the first build.
# Top-level *.h only: OpenSSL installs its headers under include/openssl/,
# and they are not part of the framework.
cp "$BUILD_DIR/stage-${ARCHS[0]}$INSTALL_PREFIX/include/"*.h "$version_dir/Headers/"
cat > "$version_dir/Modules/module.modulemap" <<'MODULEMAP'
framework module FreeTDS {
    header "tds_sysdep_public.h"
    header "sybdb.h"
    export *
}
MODULEMAP

# FreeTDS and OpenSSL call stat and friends, so the framework declares
# them, as Apple asks of third-party SDKs.
cp "$PRIVACY_MANIFEST" "$version_dir/Resources/PrivacyInfo.xcprivacy"
cat > "$version_dir/Resources/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>en</string>
    <key>CFBundleExecutable</key>
    <string>FreeTDS</string>
    <key>CFBundleIdentifier</key>
    <string>com.oliwonders.FreeTDS</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>FreeTDS</string>
    <key>CFBundlePackageType</key>
    <string>FMWK</string>
    <key>CFBundleShortVersionString</key>
    <string>$FREETDS_VERSION</string>
    <key>CFBundleVersion</key>
    <string>$FREETDS_VERSION</string>
    <key>CFBundleSupportedPlatforms</key>
    <array>
        <string>MacOSX</string>
    </array>
    <key>LSMinimumSystemVersion</key>
    <string>$MACOSX_DEPLOYMENT_TARGET</string>
</dict>
</plist>
PLIST

# The standard macOS framework layout: everything in Versions/A, reached
# through symlinks.
(
    cd "$FRAMEWORK"
    ln -s A Versions/Current
    ln -s Versions/Current/FreeTDS FreeTDS
    ln -s Versions/Current/Headers Headers
    ln -s Versions/Current/Modules Modules
    ln -s Versions/Current/Resources Resources
)

echo "==> Creating $XCFRAMEWORK"
rm -rf "$XCFRAMEWORK"
mkdir -p "$(dirname "$XCFRAMEWORK")"
xcodebuild -create-xcframework -framework "$FRAMEWORK" -output "$XCFRAMEWORK"

echo ""
echo "Verifying slices, deployment target and install name:"
lib="$(find "$XCFRAMEWORK" -path '*FreeTDS.framework/Versions/A/FreeTDS' -print -quit)"
lipo -info "$lib"
for arch in "${ARCHS[@]}"; do
    echo -n "  $arch: "
    vtool -arch "$arch" -show-build "$lib" 2>/dev/null | grep -E "minos|platform" | tr -s ' \n' ' '
    echo ""
done
otool -D "$lib" | tail -1
# Only system libraries: OpenSSL is inside, not a dependency.
# Dependency lines start with a tab; the others name each architecture.
if otool -L "$lib" | grep $'^\t' | grep -v -e "@rpath/FreeTDS.framework" -e "/usr/lib/" -e "/System/Library/"; then
    echo "❌ Unexpected dependency above"
    exit 1
fi

# Nothing from this machine should be baked into the shipped binary.
if strings -a "$lib" | grep -q -e "$BUILD_DIR" -e "$HOME"; then
    echo "❌ Build paths found in the archive:"
    strings -a "$lib" | grep -e "$BUILD_DIR" -e "$HOME" | sort -u | head
    exit 1
fi
grep -q "dbsetltlsverify" "$XCFRAMEWORK"/*/FreeTDS.framework/Headers/sybdb.h || { echo "❌ FreeTDS patches missing from headers"; exit 1; }

# Sign the XCFramework so an app's build can tell where it came from and that
# it hasn't changed since; Apple expects third-party binary SDKs to be signed.
# Use a Developer ID Application or Apple Distribution identity (name or SHA-1,
# from `security find-identity -v -p codesigning`).
if [ -n "${FREETDSKIT_CODESIGN_IDENTITY:-}" ]; then
    echo "==> Signing $XCFRAMEWORK"
    # The framework inside, then the XCFramework around it. Apps re-sign the
    # framework with their own identity when they embed it.
    codesign --force --timestamp --sign "$FREETDSKIT_CODESIGN_IDENTITY" \
        "$XCFRAMEWORK"/*/FreeTDS.framework/Versions/A
    codesign --timestamp --sign "$FREETDSKIT_CODESIGN_IDENTITY" "$XCFRAMEWORK"
    codesign --verify --strict --verbose=2 "$XCFRAMEWORK"
else
    echo "⚠️  Not signed. Set FREETDSKIT_CODESIGN_IDENTITY and run again before tagging a release."
fi

echo "✅ FreeTDS $FREETDS_VERSION + OpenSSL $OPENSSL_VERSION -> Frameworks/FreeTDS.xcframework (dynamic)"
