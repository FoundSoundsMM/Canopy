#!/bin/sh
# headless compile/load check for lib/Engine_Woodland.sc against SuperCollider
# + the norns-sc quark (CroneEngine). requires SuperCollider installed
# (`brew install --cask supercollider`) and the norns-sc quark
# (`Quarks.install("https://github.com/madskjeldgaard/norns-sc")`) -- see
# the README for the full setup.
set -e

SCLANG="${SCLANG:-/Applications/SuperCollider.app/Contents/MacOS/sclang}"
if [ ! -x "$SCLANG" ]; then
  echo "sclang not found at $SCLANG -- install SuperCollider first (see README)" >&2
  exit 1
fi

DIR="$(cd "$(dirname "$0")" && pwd)"

# the class compiler only scans SC's own Extensions folder, so the engine
# needs to be reachable from there; a symlink keeps it live against edits.
EXT_DIR="$HOME/Library/Application Support/SuperCollider/Extensions/Woodland"
mkdir -p "$EXT_DIR"
ln -sf "$DIR/../lib/Engine_Woodland.sc" "$EXT_DIR/Engine_Woodland.sc"

"$SCLANG" "$DIR/sc_check.scd"
