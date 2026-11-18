#!/bin/bash
# Live test: dictating into a terminal must type text but never press Enter.
# A foot window runs `read -t`; if read times out the line was never submitted.
set -uo pipefail
clip=$(readlink -f "${1:?usage: e2e-terminal.sh clip.wav}")
T=$(mktemp -d); prev_src=$(pactl get-default-source); prev_win=$(hyprctl activewindow -j | jq -r '.address // empty')
mod=$(pactl load-module module-null-sink sink_name=justsay_vmic channel_map=mono rate=16000)
trap 'pactl set-default-source "$prev_src"; pactl unload-module "$mod"; [[ -n $prev_win ]] && hyprctl dispatch focuswindow "address:$prev_win" >/dev/null; rm -rf "$T"' EXIT
pactl set-default-source justsay_vmic.monitor
probe="$(dirname "$(readlink -f "$0")")/tty-probe.py"
foot --app-id justsay-e2e-term -e python3 -I -B "$probe" "$T/raw" 14 >/dev/null 2>&1 &
for _ in $(seq 1 100); do hyprctl clients -j | jq -e 'any(.[]; .class=="justsay-e2e-term")' >/dev/null && break; sleep 0.1; done
sleep 0.3; hyprctl dispatch focuswindow class:justsay-e2e-term >/dev/null; sleep 0.2
[[ $(hyprctl activewindow -j | jq -r .class) == justsay-e2e-term ]] || { echo "FAIL: could not focus test window"; exit 1; }
( while sleep 0.1; do [[ -e $T/raw || -e $T/stop ]] && break; c=$(hyprctl activewindow -j | jq -r .class); [[ $c == justsay-e2e-term ]] || { voxtype record cancel; touch "$T/aborted"; echo "ABORT: focus moved to $c" >&2; break; }; done ) &
guard=$!
omarchy-dictation toggle; sleep 0.3; pw-play --target justsay_vmic "$clip"
[[ -e $T/aborted ]] && { echo "SKIPPED: focus changed during the test (keep hands off for ~10 s)"; exit 2; }; sleep 0.3; omarchy-dictation toggle
for _ in $(seq 1 100); do [[ $(voxtype status) == idle ]] && break; sleep 0.1; done
sleep 1; touch "$T/stop"; wait "$guard" 2>/dev/null
for _ in $(seq 1 200); do [[ -e $T/raw ]] && break; sleep 0.1; done
[[ -e $T/aborted ]] && { echo "SKIPPED: focus changed"; exit 2; }
text=$(tr -d '\r\n' <"$T/raw")
echo "typed=[$text]  bytes=$(wc -c <"$T/raw")  CR=$(tr -cd '\r' <"$T/raw" | wc -c)  LF=$(tr -cd '\n' <"$T/raw" | wc -c)"
if [[ -n $text ]] && [[ $(tr -cd '\r\n' <"$T/raw" | wc -c) == 0 ]]; then
  echo "PASS: text typed into the terminal, Enter never sent"
else echo "FAIL"; exit 1; fi
