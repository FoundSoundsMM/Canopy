#!/bin/sh
# offline test run -- stubs norns and drives the scheduler on a virtual clock.
# needs `lua` on PATH; nothing here touches hardware or SuperCollider.
#   sh test/run.sh
set -e
ROOT=$(cd "$(dirname "$0")/.." && pwd)
export ROOT SP="$ROOT/test"
echo "== rhythm =="; lua "$SP/rhythm.lua"
echo; echo "== weave =="; lua "$SP/weave.lua"
echo; echo "== climate =="; lua "$SP/climate.lua"
echo; echo "== groove =="; lua "$SP/groove.lua"
echo; echo "== decay =="; lua "$SP/decay.lua"
echo; echo "== exciter =="; lua "$SP/exciter.lua"
echo; echo "== heartwood =="; lua "$SP/heartwood.lua"
echo; echo "== grove =="; lua "$SP/grove.lua"
echo; echo "== voice =="; lua "$SP/voice.lua"
echo; echo "== smoke =="; lua "$SP/smoke.lua"
echo; echo "== perf =="; lua "$SP/perf.lua"
