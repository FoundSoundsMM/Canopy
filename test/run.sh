#!/bin/sh
# offline test run -- stubs norns and drives the scheduler on a virtual clock.
# needs `lua` on PATH; nothing here touches hardware or SuperCollider.
#   sh test/run.sh
set -e
ROOT=$(cd "$(dirname "$0")/.." && pwd)
export ROOT SP="$ROOT/test"
echo "== rhythm =="; lua "$SP/rhythm.lua"
echo; echo "== smoke =="; lua "$SP/smoke.lua"
echo; echo "== perf =="; lua "$SP/perf.lua"
