#!/bin/bash
set -euo pipefail

FREETDS_VERSION="1.5.2"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUILD_DIR="$SCRIPT_DIR/build"
PREFIX_DIR="$BUILD_DIR/static-freetds"

mkdir -p "$BUILD_DIR"
cd "$BUILD_DIR"
curl -LO "ftp://ftp.freetds.org/pub/freetds/stable/freetds-${FREETDS_VERSION}.tar.gz"
tar xzf "freetds-${FREETDS_VERSION}.tar.gz"
cd "freetds-${FREETDS_VERSION}"

./configure --disable-shared --enable-static --prefix="$PREFIX_DIR"
make
make install

cp -R "$PREFIX_DIR/include" "$SCRIPT_DIR/../Sources/CFreeTDS/"
echo "✅ Copied headers to Sources/CFreeTDS/include"

cp "$PREFIX_DIR/lib/libsybdb.a" "$SCRIPT_DIR/../Sources/CFreeTDS/"
echo "✅ Copied libsybdb.a to Sources/CFreeTDS/"
