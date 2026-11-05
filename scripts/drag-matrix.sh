#!/bin/sh
# Runs drag-test.swift in every pace, in tap and in monitor mode, each against a baseline taken with DockPin quit.
# Usage: scripts/drag-matrix.sh [DockPin.app] [output folder]
#   DockPin.app (default ~/Applications/DockPin.app) is quit, started and quit again here; monitor mode is forced with the
#   monitorMode default, removed afterwards. The calling terminal needs Accessibility. Results: <out>/<mode>-<pace>.txt.
#   Paces: slow, normal and fast wait for the pointer and the window after each move (exact positions); 1000hz and
#   125hz send moves at a mouse's rate (6 pt at 1000 a second, 24 pt at 125: a fast hand), as a hand does.
#   Env: MODES (default "tap monitor"), PACES (default all five).
set -u
root=$(cd "$(dirname "$0")/.." && pwd)
app="${1:-$HOME/Applications/DockPin.app}"
out="${2:-$(mktemp -d)}"
mkdir -p "$out"
paces="${PACES:-slow normal fast 1000hz 125hz}"
modes="${MODES:-tap monitor}"
flags() {
    case "$1" in
        1000hz) echo "--speed normal --hz 1000" ;;
        125hz) echo "--speed fast --hz 125" ;;
        *) echo "--speed $1" ;;
    esac
}
start() { "$app/Contents/MacOS/DockPin" >/dev/null 2>&1 & sleep 6; }
stop() { pkill -x DockPin; sleep 3; }
measure() {  # mode pace
    # shellcheck disable=SC2046 # flags are words
    swift "$root/scripts/drag-test.swift" $(flags "$2") --baseline "$out/baseline-$2.tsv" > "$out/$1-$2.txt" 2>/dev/null
    echo "$1 $2: $(tail -n 1 "$out/$1-$2.txt")"
}

stop
for p in $paces; do measure alone "$p"; done
for mode in $modes; do
    if [ "$mode" = monitor ]; then defaults write io.bringes.DockPin monitorMode -bool YES; else defaults delete io.bringes.DockPin monitorMode 2>/dev/null; fi
    start
    for p in $paces; do measure "$mode" "$p"; done
    stop
done
defaults delete io.bringes.DockPin monitorMode 2>/dev/null
echo "failures:"
grep -H "^FAIL" "$out"/tap-*.txt "$out"/monitor-*.txt | sed "s|$out/||"
echo "results in $out"
