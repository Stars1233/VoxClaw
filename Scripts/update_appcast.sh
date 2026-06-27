#!/usr/bin/env bash
# Insert a new release item into a Sparkle appcast (newest-first).
#
# Usage: update_appcast.sh <appcast.xml> <short_version> <build> <url> <ed_signature> <length>
#
# Idempotent: if an item with the same <sparkle:version> (build) already exists,
# it does nothing.
set -euo pipefail

APPCAST="$1"; SHORT="$2"; BUILD="$3"; URL="$4"; SIG="$5"; LEN="$6"
PUBDATE="$(date -u "+%a, %d %b %Y %H:%M:%S +0000")"

if grep -q "<sparkle:version>${BUILD}</sparkle:version>" "$APPCAST"; then
  echo "appcast already contains build ${BUILD}; nothing to do."
  exit 0
fi

read -r -d '' ITEM <<ITEMEOF || true
    <item>
      <title>VoxClaw ${SHORT}</title>
      <link>https://github.com/malpern/VoxClaw/releases/tag/v${SHORT}</link>
      <sparkle:version>${BUILD}</sparkle:version>
      <sparkle:shortVersionString>${SHORT}</sparkle:shortVersionString>
      <sparkle:minimumSystemVersion>26.0</sparkle:minimumSystemVersion>
      <pubDate>${PUBDATE}</pubDate>
      <description><![CDATA[<p>See the <a href="https://github.com/malpern/VoxClaw/releases/tag/v${SHORT}">release notes</a>.</p>]]></description>
      <enclosure url="${URL}" sparkle:edSignature="${SIG}" length="${LEN}" type="application/octet-stream" />
    </item>
ITEMEOF

# Insert the new item immediately after the <language> line so newest is first.
python3 - "$APPCAST" "$ITEM" <<'PY'
import sys
path, item = sys.argv[1], sys.argv[2]
s = open(path).read()
marker = "<language>en</language>"
i = s.index(marker) + len(marker)
open(path, "w").write(s[:i] + "\n" + item + s[i:])
PY

echo "appcast updated: VoxClaw ${SHORT} (build ${BUILD})"
