#!/bin/bash
# Find the newest stable FreeTDS and OpenSSL releases and, unless --check is
# given, pin them in Support/buildandlinkfreetds.sh: version and SHA-256.
#
#   Support/bump-upstream.sh --check   report only; exit 0
#   Support/bump-upstream.sh           update the pins for anything newer
#
# Release candidates are never picked. OpenSSL stays on the pinned series
# (3.5, an LTS); security fixes ship as patch releases within it.
#
# A checksum is pinned only when two independent sources agree on it:
#   FreeTDS  freetds.org's MD5 for the .tar.gz, and the SHA-256 GitHub records
#            for the release's .tar.bz2, whose unpacked tree must match the
#            .tar.gz's file for file. FreeTDS's GitHub releases lag freetds.org,
#            so a release without one yet is reported and left for later.
#   OpenSSL  openssl.org's .sha256 file and GitHub's recorded SHA-256.
#
# Needs curl, gh (signed in, or GH_TOKEN set), shasum and tar. Writes a summary
# to $SUMMARY_FILE if set, and key=value lines to $GITHUB_OUTPUT if set:
#   freetds_current, freetds_latest, openssl_current, openssl_latest, changed
set -euo pipefail
# A colouring GREP_OPTIONS in the environment would put escape codes in output.
unset GREP_OPTIONS

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUILD_SCRIPT="$SCRIPT_DIR/buildandlinkfreetds.sh"
CHECK_ONLY=false
[ "${1:-}" = "--check" ] && CHECK_ONLY=true

# 1.5.21 or 1.6 (FreeTDS drops the .0 from a new minor version).
VERSION_RE='^[0-9]+\.[0-9]+(\.[0-9]+)?$'

valid_version() { [[ "$1" =~ $VERSION_RE ]]; }

# True when $2 is a newer version than $1.
newer() { [ "$1" != "$2" ] && [ "$(printf '%s\n%s\n' "$1" "$2" | sort -V | tail -1)" = "$2" ]; }

pin() { sed -n "s/^$1=\"\(.*\)\"$/\1/p" "$BUILD_SCRIPT"; }

set_pin() {
    local name="$1" value="$2"
    # Values reaching sed are validated versions or 64-hex checksums.
    sed -i.bak "s/^$name=\".*\"$/$name=\"$value\"/" "$BUILD_SCRIPT"
    rm -f "$BUILD_SCRIPT.bak"
    [ "$(pin "$name")" = "$value" ] || { echo "❌ couldn't set $name"; exit 1; }
}

output() { [ -n "${GITHUB_OUTPUT:-}" ] && echo "$1=$2" >> "$GITHUB_OUTPUT" || true; }
summary() { echo "$1"; [ -n "${SUMMARY_FILE:-}" ] && echo "$1" >> "$SUMMARY_FILE" || true; }

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

latest_freetds() {
    curl -fsSL https://www.freetds.org/files/stable/ \
        | grep --color=never -oE 'freetds-[0-9]+\.[0-9]+(\.[0-9]+)?\.tar\.gz' \
        | sed 's/^freetds-//; s/\.tar\.gz$//' | sort -uV | tail -1
}

latest_openssl() {
    local series="${1%.*}"
    gh api "repos/openssl/openssl/releases?per_page=100" --jq '.[] | select(.prerelease|not) | .tag_name' \
        | grep --color=never -E "^openssl-${series//./\\.}\.[0-9]+$" | sed 's/^openssl-//' | sort -V | tail -1
}

# SHA-256 GitHub records for a release asset, or nothing.
github_digest() {
    local repo="$1" tag="$2" asset="$3"
    gh api "repos/$repo/releases/tags/$tag" \
        --jq ".assets[] | select(.name == \"$asset\") | .digest" 2>/dev/null \
        | sed -n 's/^sha256:\([0-9a-f]\{64\}\)$/\1/p'
}

# Prints the verified SHA-256 of freetds-$1.tar.gz, or fails with a reason.
freetds_sha256() {
    local v="$1" dir="$WORK/freetds-$v"
    mkdir -p "$dir/gz" "$dir/bz"
    local gz="$dir/freetds-$v.tar.gz" bz="$dir/freetds-$v.tar.bz2"
    curl -fsSL -o "$gz" "https://www.freetds.org/files/stable/freetds-$v.tar.gz"

    local md5
    md5="$(curl -fsSL "https://www.freetds.org/files/stable/freetds-$v.tar.gz.md5" \
        | tr -d '\r' | sed -n 's/.*= *\([0-9a-f]\{32\}\).*/\1/p')"
    [ -n "$md5" ] && [ "$(md5sum_of "$gz")" = "$md5" ] \
        || { echo "freetds.org's MD5 for $v doesn't match the download" >&2; return 1; }

    local digest
    digest="$(github_digest FreeTDS/freetds "v$v" "freetds-$v.tar.bz2")"
    [ -n "$digest" ] \
        || { echo "FreeTDS $v has no GitHub release with a .tar.bz2 yet" >&2; return 1; }
    curl -fsSL -o "$bz" "https://github.com/FreeTDS/freetds/releases/download/v$v/freetds-$v.tar.bz2"
    [ "$(shasum -a 256 "$bz" | cut -d' ' -f1)" = "$digest" ] \
        || { echo "GitHub's .tar.bz2 for $v doesn't match its recorded SHA-256" >&2; return 1; }

    tar -xzf "$gz" -C "$dir/gz"
    tar -xjf "$bz" -C "$dir/bz"
    diff -r "$dir/gz" "$dir/bz" > /dev/null \
        || { echo "freetds.org's and GitHub's sources for $v differ" >&2; return 1; }

    shasum -a 256 "$gz" | cut -d' ' -f1
}

# Prints the verified SHA-256 of openssl-$1.tar.gz, or fails with a reason.
openssl_sha256() {
    local v="$1" org gh_digest
    org="$(curl -fsSL "https://www.openssl.org/source/openssl-$v.tar.gz.sha256" \
        | tr -d '\r' | grep --color=never -oE '^[0-9a-f]{64}')"
    gh_digest="$(github_digest openssl/openssl "openssl-$v" "openssl-$v.tar.gz")"
    [ -n "$org" ] && [ "$org" = "$gh_digest" ] \
        || { echo "openssl.org and GitHub disagree on, or lack, the SHA-256 for $v" >&2; return 1; }
    echo "$org"
}

md5sum_of() {
    if command -v md5 > /dev/null; then md5 -q "$1"; else md5sum "$1" | cut -d' ' -f1; fi
}

freetds_current="$(pin FREETDS_VERSION)"
openssl_current="$(pin OPENSSL_VERSION)"
freetds_latest="$(latest_freetds)"
openssl_latest="$(latest_openssl "$openssl_current")"

for v in "$freetds_current" "$openssl_current" "$freetds_latest" "$openssl_latest"; do
    valid_version "$v" || { echo "❌ unexpected version string: '$v'"; exit 1; }
done

output freetds_current "$freetds_current"
output freetds_latest "$freetds_latest"
output openssl_current "$openssl_current"
output openssl_latest "$openssl_latest"

summary "FreeTDS: pinned $freetds_current, latest stable $freetds_latest"
summary "OpenSSL: pinned $openssl_current, latest $openssl_latest in the ${openssl_current%.*} series"

changed=false
if newer "$freetds_current" "$freetds_latest"; then
    if $CHECK_ONLY; then
        changed=true
    elif sha="$(freetds_sha256 "$freetds_latest")"; then
        set_pin FREETDS_VERSION "$freetds_latest"
        set_pin FREETDS_SHA256 "$sha"
        summary "- FreeTDS $freetds_current → $freetds_latest (SHA-256 $sha, checked against freetds.org's MD5 and GitHub's release)"
        changed=true
    else
        summary "- FreeTDS $freetds_latest not pinned: checksum couldn't be confirmed from two sources yet"
    fi
fi
if newer "$openssl_current" "$openssl_latest"; then
    if $CHECK_ONLY; then
        changed=true
    elif sha="$(openssl_sha256 "$openssl_latest")"; then
        set_pin OPENSSL_VERSION "$openssl_latest"
        set_pin OPENSSL_SHA256 "$sha"
        summary "- OpenSSL $openssl_current → $openssl_latest (SHA-256 $sha, from openssl.org and GitHub)"
        changed=true
    else
        summary "- OpenSSL $openssl_latest not pinned: checksum couldn't be confirmed from two sources"
    fi
fi

output changed "$changed"
$changed || summary "Nothing to update."
