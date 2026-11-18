#!/bin/bash
# Live end-to-end test on a real Omarchy session (needs Hyprland, PipeWire,
# foot, nvim, and a working `justsay install`). Uses the real cloud path.
#
#   tests/e2e.sh clip.wav [expected-substring]
#
# A temporary virtual microphone plays the clip, a throwaway foot+nvim window
# receives the typed text, and the inserted text is read back over nvim's RPC
# socket. Then it checks that the text was inserted exactly once and that no
# newline was typed. The default source, focus and module are restored on exit.
set -uo pipefail
clip=${1:?usage: e2e.sh clip.wav [expected]}; expect=${2:-}
clip=$(readlink -f "$clip")
T=$(mktemp -d); sock="$T/nvim.sock"
prev_src=$(pactl get-default-source)
prev_win=$(hyprctl activewindow -j | jq -r '.address // empty')
mod=""
cleanup() {
  [[ -S $sock ]] && nvim --server "$sock" --remote-send '<C-\><C-N>:qa!<CR>' >/dev/null 2>&1
  pactl set-default-source "$prev_src" >/dev/null 2>&1
  [[ -n $mod ]] && pactl unload-module "$mod" >/dev/null 2>&1
  [[ -n $prev_win ]] && hyprctl dispatch focuswindow "address:$prev_win" >/dev/null 2>&1
  rm -rf "$T"
}
trap cleanup EXIT

state() { voxtype status 2>/dev/null; }
wait_state() { local want=$1 _i; for _i in $(seq 1 ${2:-100}); do [[ $(state) == "$want" ]] && return 0; sleep 0.1; done; return 1; }

mod=$(pactl load-module module-null-sink sink_name=justsay_vmic channel_map=mono rate=16000)
pactl set-default-source justsay_vmic.monitor

foot --app-id justsay-e2e -e nvim --clean --listen "$sock" -c startinsert "$T/out.txt" >/dev/null 2>&1 &
for _ in $(seq 1 100); do [[ -S $sock ]] && hyprctl clients -j | jq -e 'any(.[]; .class=="justsay-e2e")' >/dev/null && break; sleep 0.1; done
sleep 0.3
hyprctl dispatch focuswindow class:justsay-e2e >/dev/null; sleep 0.2
[[ $(hyprctl activewindow -j | jq -r .class) == justsay-e2e ]] || { echo "FAIL: could not focus test window"; exit 1; }
# Safety: if focus ever leaves the test window, cancel so nothing types elsewhere.
( while sleep 0.1; do c=$(hyprctl activewindow -j | jq -r .class); [[ $c == justsay-e2e ]] || { voxtype record cancel; touch "$T/aborted"; echo "ABORT: focus moved to $c" >&2; break; }; [[ -e $T/done ]] && break; done ) &
guard=$!

t0=$(date +%s%N)
omarchy-dictation toggle || { echo "FAIL: omarchy-dictation toggle refused to start"; exit 1; }
wait_state recording 30 || { echo "FAIL: never entered recording"; exit 1; }
sleep 0.3
pw-play --target justsay_vmic "$clip"
[[ -e $T/aborted ]] && { echo "SKIPPED: focus changed during the test (keep hands off for ~10 s)"; exit 2; }
sleep 0.4
omarchy-dictation toggle
wait_state transcribing 20 || true
wait_state idle 400 || { echo "FAIL: did not return to idle"; exit 1; }
sleep 0.8
t1=$(date +%s%N)
touch "$T/done"; wait $guard 2>/dev/null

lines=$(nvim --server "$sock" --remote-expr 'line("$")')
text=$(nvim --server "$sock" --remote-expr 'join(getline(1,"$"),"\n")')
printf 'inserted: %s\n' "$text"
printf 'wall time incl. playback: %d ms\n' $(( (t1 - t0) / 1000000 ))
rc=0
[[ -n $text ]] || { echo "FAIL: nothing inserted"; rc=1; }
[[ $lines == 1 ]] || { echo "FAIL: newline typed ($lines lines)"; rc=1; }
if [[ -n $expect ]]; then
  n=$(grep -o -F -- "$expect" <<<"$text" | wc -l)
  [[ $n == 1 ]] || { echo "FAIL: expected '$expect' exactly once, found $n"; rc=1; }
fi
(( rc == 0 )) && echo PASS
exit $rc
