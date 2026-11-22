#!/usr/bin/env bash
# Download the pinned OSS CAD Suite release into tools/oss-cad-suite.
# usage: scripts/fetch_toolchain.sh [linux-x64|linux-arm64|darwin-x64|darwin-arm64|windows-x64]
set -euo pipefail
DATE=2026-11-01                 # the project's pinned release; change only with a decision record
PLAT=${1:-linux-x64}
ROOT=$(cd "$(dirname "$0")/.." && pwd)
mkdir -p "$ROOT/tools" && cd "$ROOT/tools"
ext=tgz; [[ $PLAT == windows-* ]] && ext=exe
f="oss-cad-suite-$PLAT-${DATE//-/}.$ext"
curl -fSL -o "$f" "https://github.com/YosysHQ/oss-cad-suite-build/releases/download/$DATE/$f"
if [ "$ext" = tgz ]; then tar xzf "$f" && rm "$f"; else echo "Run $f to unpack (self-extracting)"; fi
echo "Add to PATH: $ROOT/tools/oss-cad-suite/bin"
