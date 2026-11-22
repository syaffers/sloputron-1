#!/usr/bin/env bash
# Fetch the third-party baseline cores at the exact revisions used for docs/phase0/baselines.md.
# usage: scripts/fetch_baselines.sh [dest]   (default: ext/)
set -euo pipefail
DEST=${1:-$(cd "$(dirname "$0")/.." && pwd)/ext}
mkdir -p "$DEST"
while read -r name url rev; do
  [ -z "$name" ] && continue
  d="$DEST/$name"
  if [ ! -d "$d/.git" ]; then git init -q "$d"; git -C "$d" remote add origin "$url"; fi
  git -C "$d" fetch -q --depth 1 origin "$rev"
  git -C "$d" checkout -q --detach FETCH_HEAD
  echo "$name $(git -C "$d" rev-parse --short HEAD)"
done <<'EOF'
swapforth  https://github.com/jamesbowman/swapforth.git  0c520f06ea88f971b2aeb323fbe18687ce6b1bb6
serv       https://github.com/olofk/serv.git             f200eb2ed7b69ac1c6b8eddd47654522aeee5ce8
minimax    https://github.com/gsmecher/minimax.git       9d443f5fe5c9147bff1a86ee8758fb82cfb2d78c
learn-fpga https://github.com/BrunoLevy/learn-fpga.git   f5ada24ae6cca67d99889daec2c4ee44a6e59417
picorv32   https://github.com/YosysHQ/picorv32.git       ef203c2b0a3fb793280f5114941416c425c5b461
leros      https://github.com/leros-dev/leros.git         3909a8aecdcdb763175acdb020765f63c0368cbe
FazyRV     https://github.com/meiniKi/FazyRV.git         c325b917d94e7cc3bb644aa6295dd797b9ba82f6
EOF
