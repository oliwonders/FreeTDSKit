#!/bin/bash
# Build OpenSSL and FreeTDS as one dynamic framework, FreeTDS.framework, for
# three platforms, packaged together as Frameworks/FreeTDS.xcframework, which
# Package.swift consumes as a binary target:
#
#   macOS            arm64 + x86_64   macOS 15.0   versioned bundle layout
#   iOS              arm64            iOS 17.0     shallow bundle layout
#   iOS Simulator    arm64 + x86_64   iOS 17.0     shallow bundle layout
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
IPHONEOS_DEPLOYMENT_TARGET="17.0"
OPENSSL_VERSION="3.5.9"
FREETDS_VERSION="1.5.19"
# SHA-256 of each source tarball. Update alongside the version, from a source
# other than the download itself: openssl.org/source/<tarball>.sha256 (also on
# the GitHub release), and freetds.org/files/stable/<tarball>.md5 cross-checked
# against a second download.
OPENSSL_SHA256="603f5602e2eef00d77fbd429d34dcd5822bb301757a1bc9cdb24c670f1eb859a"
FREETDS_SHA256="ff70d0c8ae8dd23e7b1314274d6e9d30b479998415760b3fa656754b737c2bd6"
# Each platform becomes one slice of the XCFramework.
PLATFORMS=(macos ios iossimulator)

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PACKAGE_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
BUILD_DIR="$SCRIPT_DIR/build"
XCFRAMEWORK="$PACKAGE_DIR/Frameworks/FreeTDS.xcframework"
PRIVACY_MANIFEST="$SCRIPT_DIR/FreeTDS-PrivacyInfo.xcprivacy"
PATCH_DIR="$SCRIPT_DIR/patches"
# Where the libraries *think* they are installed. FreeTDS and OpenSSL compile
# their prefix into the binary as the place to look for freetds.conf,
# openssl.cnf and CA certificates, so a prefix under this checkout would ship
# your home folder path inside every app and point those lookups at it. The
# real install goes to a per-arch staging directory via DESTDIR.
INSTALL_PREFIX="/usr/local/freetdskit"
NCPU="$(sysctl -n hw.logicalcpu)"

# Everything that differs between platforms. Sets, for platform $1:
#   P_ARCHS          architectures lipo'd into the slice
#   P_SDK            xcrun SDK name
#   P_MIN            deployment target
#   P_MIN_FLAG       compiler flag carrying the deployment target
#   P_VTOOL          platform name vtool -show-build reports (LC_BUILD_VERSION)
#   P_PLIST_PLATFORM CFBundleSupportedPlatforms entry
#   P_LAYOUT         "versioned" (macOS) or "shallow" (iOS)
#   P_XCF_ID         the slice's directory inside the XCFramework
platform_settings() {
    case "$1" in
        macos)
            P_ARCHS="arm64 x86_64"
            P_SDK="macosx"
            P_MIN="$MACOSX_DEPLOYMENT_TARGET"
            P_MIN_FLAG="-mmacosx-version-min=$P_MIN"
            P_VTOOL="MACOS"
            P_PLIST_PLATFORM="MacOSX"
            P_LAYOUT="versioned"
            P_XCF_ID="macos-arm64_x86_64"
            ;;
        ios)
            P_ARCHS="arm64"
            P_SDK="iphoneos"
            P_MIN="$IPHONEOS_DEPLOYMENT_TARGET"
            P_MIN_FLAG="-mios-version-min=$P_MIN"
            P_VTOOL="IOS"
            P_PLIST_PLATFORM="iPhoneOS"
            P_LAYOUT="shallow"
            P_XCF_ID="ios-arm64"
            ;;
        iossimulator)
            P_ARCHS="arm64 x86_64"
            P_SDK="iphonesimulator"
            P_MIN="$IPHONEOS_DEPLOYMENT_TARGET"
            P_MIN_FLAG="-mios-simulator-version-min=$P_MIN"
            P_VTOOL="IOSSIMULATOR"
            P_PLIST_PLATFORM="iPhoneSimulator"
            P_LAYOUT="shallow"
            P_XCF_ID="ios-arm64_x86_64-simulator"
            ;;
        *)
            echo "❌ Unknown platform $1"
            exit 1
            ;;
    esac
}

# The framework's library, relative to FreeTDS.framework, and its install name.
library_in_framework() {
    if [ "$P_LAYOUT" = "versioned" ]; then echo "Versions/A/FreeTDS"; else echo "FreeTDS"; fi
}
install_name() {
    echo "@rpath/FreeTDS.framework/$(library_in_framework)"
}

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

# Build OpenSSL and FreeTDS for one platform and architecture and link them
# into $BUILD_DIR/FreeTDS-<platform>-<arch>, a thin dynamic library. Runs in a
# subshell so each platform's environment stays its own.
build_arch() (
    local platform="$1" arch="$2"
    platform_settings "$platform"

    local openssl_target host
    case "$platform-$arch" in
        macos-arm64)         openssl_target="darwin64-arm64-cc";         host="aarch64-apple-darwin" ;;
        macos-x86_64)        openssl_target="darwin64-x86_64-cc";        host="x86_64-apple-darwin" ;;
        ios-arm64)           openssl_target="ios64-xcrun";               host="aarch64-apple-ios" ;;
        iossimulator-arm64)  openssl_target="iossimulator-arm64-xcrun";  host="aarch64-apple-ios" ;;
        iossimulator-x86_64) openssl_target="iossimulator-x86_64-xcrun"; host="x86_64-apple-ios" ;;
        *) echo "❌ No build settings for $platform-$arch"; exit 1 ;;
    esac

    local src_dir="$BUILD_DIR/src-$platform-$arch"
    local stage_dir="$BUILD_DIR/stage-$platform-$arch"
    local staged="$stage_dir$INSTALL_PREFIX"
    local cflags="-arch $arch $P_MIN_FLAG"

    if [ "$platform" = "macos" ]; then
        export MACOSX_DEPLOYMENT_TARGET
    else
        # clang and ld find the SDK through SDKROOT, so no -isysroot (and no
        # path to Xcode) ends up in the compiler flags OpenSSL records in the
        # binary. The deployment target travels in $P_MIN_FLAG.
        unset MACOSX_DEPLOYMENT_TARGET
        export SDKROOT
        SDKROOT="$(xcrun --sdk "$P_SDK" --show-sdk-path)"
    fi
    # Only the OpenSSL just built: pkg-config would otherwise hand FreeTDS's
    # configure a Homebrew OpenSSL (or unixODBC) built for macOS.
    export PKG_CONFIG_LIBDIR="$staged/lib/pkgconfig"
    export PKG_CONFIG_PATH=""

    rm -rf "$src_dir" "$stage_dir"
    mkdir -p "$src_dir"

    echo "==> Building OpenSSL $OPENSSL_VERSION ($platform $arch, $P_MIN)"
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

    # FreeTDS is autoconf: --host tells configure this is a cross build, so it
    # doesn't try to run x86_64 test programs on an arm64 machine, or iOS
    # programs on a Mac. Only libsybdb goes into the framework; on iOS the
    # command-line tools, ODBC driver, server and pool aren't built at all
    # (the tools call APIs iOS doesn't have).
    local extra_configure=()
    if [ "$platform" != "macos" ]; then
        extra_configure=(--disable-apps --disable-odbc --disable-server --disable-pool)
    fi
    echo "==> Building FreeTDS $FREETDS_VERSION ($platform $arch, $P_MIN)"
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
            --prefix="$INSTALL_PREFIX" \
            ${extra_configure[@]+"${extra_configure[@]}"}
        make -j"$NCPU"
        make install DESTDIR="$stage_dir"
    )

    # One dynamic library per arch holding FreeTDS and the OpenSSL it was
    # built against, so the three can never drift apart. -all_load keeps
    # every symbol: what's used is decided when an app links.
    clang -dynamiclib $cflags \
        -install_name "$(install_name)" \
        -compatibility_version 1.0 -current_version "$FREETDS_VERSION" \
        -Wl,-all_load \
        "$staged/lib/libsybdb.a" \
        "$staged/lib/libssl.a" \
        "$staged/lib/libcrypto.a" \
        -liconv \
        -o "$BUILD_DIR/FreeTDS-$platform-$arch"
)

# The framework's Info.plist. macOS takes LSMinimumSystemVersion; iOS takes
# MinimumOSVersion and UIDeviceFamily (1 iPhone, 2 iPad), which App Store
# validation checks on every embedded framework.
write_info_plist() {
    local plist="$1" min_key min_extra=""
    local sdk_version sdk_build
    sdk_version="$(xcrun --sdk "$P_SDK" --show-sdk-version)"
    sdk_build="$(xcrun --sdk "$P_SDK" --show-sdk-build-version)"
    if [ "$P_LAYOUT" = "versioned" ]; then
        min_key="LSMinimumSystemVersion"
    else
        min_key="MinimumOSVersion"
        min_extra="    <key>UIDeviceFamily</key>
    <array>
        <integer>1</integer>
        <integer>2</integer>
    </array>
"
    fi
    cat > "$plist" <<PLIST
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
        <string>$P_PLIST_PLATFORM</string>
    </array>
    <key>$min_key</key>
    <string>$P_MIN</string>
${min_extra}    <key>DTPlatformName</key>
    <string>$P_SDK</string>
    <key>DTPlatformVersion</key>
    <string>$sdk_version</string>
    <key>DTSDKName</key>
    <string>$P_SDK$sdk_version</string>
    <key>DTSDKBuild</key>
    <string>$sdk_build</string>
</dict>
</plist>
PLIST
    plutil -lint -s "$plist"
}

# Assemble $BUILD_DIR/<platform>/FreeTDS.framework from the platform's thin
# libraries.
#   macOS: the versioned layout -- everything in Versions/A, reached through
#          symlinks, resources in Resources/.
#   iOS:   the shallow layout -- library, Info.plist and privacy manifest at
#          the top of the bundle, no Versions/ and no symlinks.
assemble_framework() {
    local platform="$1"
    platform_settings "$platform"
    local framework="$BUILD_DIR/$platform/FreeTDS.framework"
    local content_dir resources_dir

    echo "==> Creating FreeTDS.framework ($platform, $P_LAYOUT layout)"
    rm -rf "$BUILD_DIR/$platform"
    if [ "$P_LAYOUT" = "versioned" ]; then
        content_dir="$framework/Versions/A"
        resources_dir="$content_dir/Resources"
    else
        content_dir="$framework"
        resources_dir="$framework"
    fi
    mkdir -p "$content_dir/Headers" "$content_dir/Modules" "$resources_dir"

    local thin_libraries=() arch first_arch=""
    for arch in $P_ARCHS; do
        thin_libraries+=("$BUILD_DIR/FreeTDS-$platform-$arch")
        [ -n "$first_arch" ] || first_arch="$arch"
    done
    lipo -create "${thin_libraries[@]}" -output "$content_dir/FreeTDS"

    # Headers are identical across arches; take them from the first build.
    # Top-level *.h only: OpenSSL installs its headers under include/openssl/,
    # and they are not part of the framework.
    /bin/cp -f "$BUILD_DIR/stage-$platform-$first_arch$INSTALL_PREFIX/include/"*.h "$content_dir/Headers/"
    cat > "$content_dir/Modules/module.modulemap" <<'MODULEMAP'
framework module FreeTDS {
    header "tds_sysdep_public.h"
    header "sybdb.h"
    export *
}
MODULEMAP

    # FreeTDS and OpenSSL call stat and friends, so the framework declares
    # them, as Apple asks of third-party SDKs.
    /bin/cp -f "$PRIVACY_MANIFEST" "$resources_dir/PrivacyInfo.xcprivacy"
    write_info_plist "$resources_dir/Info.plist"

    if [ "$P_LAYOUT" = "versioned" ]; then
        (
            cd "$framework" >/dev/null
            ln -s A Versions/Current
            ln -s Versions/Current/FreeTDS FreeTDS
            ln -s Versions/Current/Headers Headers
            ln -s Versions/Current/Modules Modules
            ln -s Versions/Current/Resources Resources
        )
    fi
}

# Check one slice of the finished XCFramework: architectures, platform and
# deployment target of each, install name, dependencies, build paths, headers
# and Info.plist. Exits on the first problem.
verify_slice() {
    local platform="$1"
    platform_settings "$platform"
    local framework="$XCFRAMEWORK/$P_XCF_ID/FreeTDS.framework"
    local lib
    lib="$framework/$(library_in_framework)"
    local plist arch build platform_seen minos_seen archs_seen id

    echo "  [$P_XCF_ID]"
    { [ -f "$lib" ] && [ ! -L "$lib" ]; } || { echo "❌ $lib missing"; exit 1; }

    archs_seen="$(lipo -archs "$lib")"
    echo "    archs: $archs_seen"
    for arch in $P_ARCHS; do
        case " $archs_seen " in *" $arch "*) ;; *) echo "❌ $arch missing"; exit 1 ;; esac
    done
    [ "$(echo "$archs_seen" | wc -w | tr -d ' ')" = "$(echo "$P_ARCHS" | wc -w | tr -d ' ')" ] \
        || { echo "❌ Unexpected architectures: $archs_seen"; exit 1; }

    for arch in $P_ARCHS; do
        build="$(vtool -arch "$arch" -show-build "$lib" 2>/dev/null)"
        platform_seen="$(echo "$build" | awk '$1 == "platform" { print $2 }')"
        minos_seen="$(echo "$build" | awk '$1 == "minos" { print $2 }')"
        echo "    $arch: platform $platform_seen minos $minos_seen"
        if [ "$platform_seen" != "$P_VTOOL" ] || [ "$minos_seen" != "$P_MIN" ]; then
            echo "❌ Expected platform $P_VTOOL minos $P_MIN"
            exit 1
        fi
    done

    id="$(otool -D "$lib" | tail -1)"
    echo "    install name: $id"
    [ "$id" = "$(install_name)" ] || { echo "❌ Expected install name $(install_name)"; exit 1; }

    # Only system libraries: OpenSSL is inside, not a dependency.
    # Dependency lines start with a tab; the others name each architecture.
    if otool -L "$lib" | grep $'^\t' | grep -v -e "$(install_name) " -e "/usr/lib/" -e "/System/Library/"; then
        echo "❌ Unexpected dependency above"
        exit 1
    fi

    # Nothing from this machine should be baked into the shipped binary.
    if strings -a "$lib" | grep -q -e "$BUILD_DIR" -e "$HOME" -e "/Applications/Xcode"; then
        echo "❌ Build paths found in the library:"
        strings -a "$lib" | grep -e "$BUILD_DIR" -e "$HOME" -e "/Applications/Xcode" | sort -u | head
        exit 1
    fi

    grep -q "dbsetltlsverify" "$framework/Headers/sybdb.h" \
        || { echo "❌ FreeTDS patches missing from headers"; exit 1; }
    [ -f "$framework/Modules/module.modulemap" ] || { echo "❌ module map missing"; exit 1; }

    if [ "$P_LAYOUT" = "versioned" ]; then
        plist="$framework/Versions/A/Resources/Info.plist"
        [ -f "$framework/Versions/A/Resources/PrivacyInfo.xcprivacy" ] || { echo "❌ privacy manifest missing"; exit 1; }
        [ "$(/usr/libexec/PlistBuddy -c 'Print :LSMinimumSystemVersion' "$plist")" = "$P_MIN" ] \
            || { echo "❌ LSMinimumSystemVersion is not $P_MIN"; exit 1; }
    else
        plist="$framework/Info.plist"
        [ ! -e "$framework/Versions" ] || { echo "❌ iOS framework must be shallow"; exit 1; }
        [ -f "$framework/PrivacyInfo.xcprivacy" ] || { echo "❌ privacy manifest missing"; exit 1; }
        [ "$(/usr/libexec/PlistBuddy -c 'Print :MinimumOSVersion' "$plist")" = "$P_MIN" ] \
            || { echo "❌ MinimumOSVersion is not $P_MIN"; exit 1; }
        /usr/libexec/PlistBuddy -c 'Print :UIDeviceFamily' "$plist" >/dev/null \
            || { echo "❌ UIDeviceFamily missing"; exit 1; }
    fi
    [ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleSupportedPlatforms:0' "$plist")" = "$P_PLIST_PLATFORM" ] \
        || { echo "❌ CFBundleSupportedPlatforms is not $P_PLIST_PLATFORM"; exit 1; }
    [ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundlePackageType' "$plist")" = "FMWK" ] \
        || { echo "❌ CFBundlePackageType is not FMWK"; exit 1; }
    echo "    size: $(du -sh "$framework" | cut -f1) (library $(( $(stat -f %z "$lib") / 1024 )) KB)"
}

for platform in "${PLATFORMS[@]}"; do
    platform_settings "$platform"
    for arch in $P_ARCHS; do
        build_arch "$platform" "$arch"
    done
done

xcframework_args=()
for platform in "${PLATFORMS[@]}"; do
    assemble_framework "$platform"
    xcframework_args+=(-framework "$BUILD_DIR/$platform/FreeTDS.framework")
done

echo "==> Creating $XCFRAMEWORK"
rm -rf "$XCFRAMEWORK"
mkdir -p "$(dirname "$XCFRAMEWORK")"
xcodebuild -create-xcframework "${xcframework_args[@]}" -output "$XCFRAMEWORK"

# The roots FreeTDSKit verifies server certificates against on iOS, which has
# no API to list its trust store; refreshed with every framework build.
echo "==> Refreshing Sources/FreeTDSKit/AppleRootCertificates.pem"
"$SCRIPT_DIR/export-apple-roots.sh"

echo ""
echo "Verifying each slice:"
for platform in "${PLATFORMS[@]}"; do
    verify_slice "$platform"
done

# Sign the XCFramework so an app's build can tell where it came from and that
# it hasn't changed since; Apple expects third-party binary SDKs to be signed.
# Use a Developer ID Application or Apple Distribution identity (name or SHA-1,
# from `security find-identity -v -p codesigning`).
if [ -n "${FREETDSKIT_CODESIGN_IDENTITY:-}" ]; then
    echo "==> Signing $XCFRAMEWORK"
    # Each framework inside, then the XCFramework around them. Apps re-sign
    # the framework with their own identity when they embed it.
    for platform in "${PLATFORMS[@]}"; do
        platform_settings "$platform"
        framework="$XCFRAMEWORK/$P_XCF_ID/FreeTDS.framework"
        if [ "$P_LAYOUT" = "versioned" ]; then
            codesign --force --timestamp --sign "$FREETDSKIT_CODESIGN_IDENTITY" "$framework/Versions/A"
        else
            codesign --force --timestamp --sign "$FREETDSKIT_CODESIGN_IDENTITY" "$framework"
        fi
        codesign --verify --strict --verbose=2 "$framework"
    done
    codesign --timestamp --sign "$FREETDSKIT_CODESIGN_IDENTITY" "$XCFRAMEWORK"
    codesign --verify --strict --verbose=2 "$XCFRAMEWORK"
else
    echo "⚠️  Not signed. Set FREETDSKIT_CODESIGN_IDENTITY and run again before tagging a release."
fi

echo "✅ FreeTDS $FREETDS_VERSION + OpenSSL $OPENSSL_VERSION -> Frameworks/FreeTDS.xcframework (dynamic; macOS, iOS, iOS Simulator)"
