#!/bin/sh
# offline test run -- stubs norns and drives the scheduler on a virtual clock.
# needs `lua` on PATH; nothing here touches hardware or SuperCollider.
#   sh test/run.sh
set -e
ROOT=$(cd "$(dirname "$0")/.." && pwd)
export ROOT SP="$ROOT/test"
echo "== rhythm =="; lua "$SP/rhythm.lua"
echo; echo "== weave =="; lua "$SP/weave.lua"
echo; echo "== clockcell =="; lua "$SP/clockcell.lua"
echo; echo "== gust =="; lua "$SP/gust.lua"
echo; echo "== lfo =="; lua "$SP/lfo.lua"
echo; echo "== groove =="; lua "$SP/groove.lua"
echo; echo "== decay =="; lua "$SP/decay.lua"
echo; echo "== exciter =="; lua "$SP/exciter.lua"
echo; echo "== sample =="; lua "$SP/sample.lua"
echo; echo "== grove =="; lua "$SP/grove.lua"
echo; echo "== voice =="; lua "$SP/voice.lua"
echo; echo "== gvoice =="; lua "$SP/gvoice.lua"
echo; echo "== tm =="; lua "$SP/tm.lua"
echo; echo "== gparam =="; lua "$SP/gparam.lua"
echo; echo "== mixer =="; lua "$SP/mixer.lua"
echo; echo "== colour =="; lua "$SP/colour.lua"
echo; echo "== screen =="; lua "$SP/screen.lua"
echo; echo "== gridui =="; lua "$SP/gridui.lua"
echo; echo "== smoke =="; lua "$SP/smoke.lua"
echo; echo "== soak =="; lua "$SP/soak.lua"
echo; echo "== perf =="; lua "$SP/perf.lua"
