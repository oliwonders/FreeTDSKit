# Generate a FreeTDS package config (.PC) file and copies it to the correct location and
# generates a link. This helps Xcode find the sysbdb.h file 

#!/bin/bash

# Find the latest installed FreeTDS version
FREETDS_DIR="/opt/homebrew/Cellar/freetds"
VERSION=$(ls -v "$FREETDS_DIR" | tail -n 1)

# Ensure we found a version
if [ -z "$VERSION" ]; then
  echo "❌ No FreeTDS installation found in $FREETDS_DIR, please run `brew install freetds`"
  exit 1
fi

PREFIX="$FREETDS_DIR/$VERSION"
PC_FILE="$PREFIX/lib/pkgconfig/freetds.pc"
LINK_TARGET="../../Cellar/freetds/$VERSION/lib/pkgconfig/freetds.pc"
LINK_NAME="/opt/homebrew/lib/pkgconfig/freetds.pc"

echo "✅ Detected FreeTDS version: $VERSION"

# Ensure the target directory exists
mkdir -p "$(dirname "$PC_FILE")"

# Create the freetds.pc file
cat <<EOF > "$PC_FILE"
prefix="$PREFIX"
libdir="\${prefix}/lib"
includedir="\${prefix}/include"

Name: freetds
Description: A free implementation of TDS protocol
Version: $VERSION
Libs: -L\${libdir} -lsybdb
Requires.Private: libssl, libcrypto
Libs.private: -liconv
Cflags: -I\${includedir}
EOF

echo "✅ Generated $PC_FILE"

# Create the symbolic link
mkdir -p "/opt/homebrew/lib/pkgconfig"
ln -sf "$LINK_TARGET" "$LINK_NAME"

echo "✅ Created symbolic link: $LINK_NAME -> $LINK_TARGET"

if output=$(pkgconf --cflags freetds 2>&1); then
    echo "✅ pkgconf output:"
    echo "$output"
else
    echo "❌ Error: pkgconf failed with the following message:"
    echo "$output"
fi
