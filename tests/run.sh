#!/bin/bash
# Offline test suite. Never touches the real $HOME, services or network.
set -uo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
export PYTHONDONTWRITEBYTECODE=1
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
pass=0; fail=0
check() { # name, command...
  local name=$1; shift
  if "$@" >"$T/out" 2>&1; then pass=$((pass+1)); printf '  ok   %s\n' "$name"
  else fail=$((fail+1)); printf '  FAIL %s\n' "$name"; sed 's/^/       /' "$T/out"; fi
}
EDIT="$ROOT/bin/justsay-edit"; PP="$ROOT/bin/justsay-postprocess"

echo "# justsay-edit (TOML)"
cat >"$T/c.toml" <<'T'
# comment stays
state_file = "auto"

[whisper]
model = "base.en"
language = "en"
# backend = "local"

[output]
mode = "type"
fallback_to_clipboard = true

[output.notification]
on_transcription = false
T
cp "$T/c.toml" "$T/orig.toml"
check "set existing key in place" bash -c "'$EDIT' toml-set '$T/c.toml' whisper language '\"auto\"' && grep -qx 'language = \"auto\"' '$T/c.toml'"
check "commented key is not treated as set" bash -c "! '$EDIT' toml-get '$T/c.toml' whisper backend"
check "new key lands inside [whisper]" bash -c "'$EDIT' toml-set '$T/c.toml' whisper backend '\"remote\"' && awk '/^\[whisper\]/{s=1;next} /^\[/{s=0} s && /^backend = \"remote\"/{f=1} END{exit !f}' '$T/c.toml'"
check "key goes to [output], not [output.notification]" bash -c "'$EDIT' toml-set '$T/c.toml' output auto_submit false && awk '/^\[output\]$/{s=1;next} /^\[/{s=0} s && /^auto_submit = false/{f=1} END{exit !f}' '$T/c.toml'"
check "new section is appended" bash -c "'$EDIT' toml-set '$T/c.toml' output.post_process command '\"/x\"' && grep -q '^\[output.post_process\]' '$T/c.toml'"
check "set is idempotent" bash -c "cp '$T/c.toml' '$T/c2' && '$EDIT' toml-set '$T/c.toml' whisper backend '\"remote\"' && cmp -s '$T/c.toml' '$T/c2'"
check "parses as TOML" python3 -I -B -c "import tomllib,sys; tomllib.load(open('$T/c.toml','rb'))"
check "restore returns the original bytes" bash -c "
  '$EDIT' toml-set '$T/c.toml' whisper language '\"en\"' &&
  '$EDIT' toml-del '$T/c.toml' whisper backend &&
  '$EDIT' toml-del '$T/c.toml' output auto_submit &&
  '$EDIT' toml-del '$T/c.toml' output.post_process command &&
  cmp '$T/c.toml' '$T/orig.toml'"

echo "# justsay-edit (JSONC menu)"
frag="$ROOT/menu/justsay.jsonc"
printf '{\n  // user comment\n  "a.b": {"label":"x"}\n}\n' >"$T/m.jsonc"; cp "$T/m.jsonc" "$T/m0"
check "add block to file with entries" bash -c "'$EDIT' jsonc-add '$T/m.jsonc' '$frag'"
check "result is valid JSON after stripping comments" python3 -I -B -c "
from importlib.machinery import SourceFileLoader as L; import json
m=L('e','$EDIT').load_module(); json.loads(m.strip_jsonc(open('$T/m.jsonc').read()))"
check "add is idempotent (one block)" bash -c "'$EDIT' jsonc-add '$T/m.jsonc' '$frag' && [ \$(grep -c '>>> justsay' '$T/m.jsonc') = 1 ]"
check "del restores original" bash -c "'$EDIT' jsonc-del '$T/m.jsonc' && diff <(grep -v '^\$' '$T/m.jsonc') <(grep -v '^\$' '$T/m0')"
printf '{\n}\n' >"$T/e.jsonc"
check "add to empty object stays valid JSON" bash -c "'$EDIT' jsonc-add '$T/e.jsonc' '$frag' && python3 -I -B -c \"
from importlib.machinery import SourceFileLoader as L; import json
m=L('e','$EDIT').load_module(); json.loads(m.strip_jsonc(open('$T/e.jsonc').read()))\""

echo "# justsay-postprocess"
printf '#!/bin/sh\necho %s\n' "'{\"address\":\"0x1\",\"class\":\"test\"}'" >"$T/focus"; chmod +x "$T/focus"
export JUSTSAY_NOTIFY_CMD=true JUSTSAY_CLIP_CMD="tee $T/clip" JUSTSAY_FOCUS_CMD="$T/focus" JUSTSAY_DICT_FILE=""
pp() { printf '%b' "$1" | "$PP"; }
check "plain text passes through" bash -c "[ \"\$(printf 'hello world' | '$PP')\" = 'hello world' ]"
check "mixed zh/en preserved" bash -c "[ \"\$(printf '我刚刚 push 了一个 commit。' | '$PP')\" = '我刚刚 push 了一个 commit。' ]"
check "newlines/CR never reach output" bash -c "out=\$(printf 'rm -rf x\nls\r\n' | '$PP'); [[ \$out != *\$'\n'* && \$out != *\$'\r'* && \$out = 'rm -rf x ls' ]]"
check "ANSI/OSC escapes and controls stripped" bash -c "out=\$(printf 'a\033[31mb\033]0;t\007c\001d\177' | '$PP'); [ \"\$out\" = 'abcd' ]"
check "bidi overrides stripped" bash -c "out=\$(printf 'ab‮cd' | '$PP'); [ \"\$out\" = 'abcd' ]"
check "empty/whitespace -> no output" bash -c "[ -z \"\$(printf ' \n\t ' | '$PP')\" ]"
check "no focus -> clipboard, nothing typed" bash -c "out=\$(printf 'secret plan' | JUSTSAY_FOCUS_CMD='echo {}' '$PP'); [ -z \"\$out\" ] && [ \"\$(cat '$T/clip')\" = 'secret plan' ]"
check "focus query failure -> clipboard" bash -c "out=\$(printf 'x' | JUSTSAY_FOCUS_CMD=false '$PP'); [ -z \"\$out\" ]"
cat >"$T/dict.json" <<'D'
{
  "replacements": {
    "vox": "WRONG_SHORT",
    "vox type": "Voxtype",
    "哦妈奇": "Omarchy",
    "hyprland": "Hyprland"
  }
}
D
check "dict replaces mixed zh/en & respects longer phrase" bash -c "[ \"\$(printf '我在哦妈奇上用 vox type 和 hyprland' | JUSTSAY_DICT_FILE='$T/dict.json' '$PP')\" = '我在Omarchy上用 Voxtype 和 Hyprland' ]"
check "dict respects ASCII word boundaries" bash -c "[ \"\$(printf 'myvoxtype voxing' | JUSTSAY_DICT_FILE='$T/dict.json' '$PP')\" = 'myvoxtype voxing' ]"
printf '{bad json' >"$T/bad.json"
check "dict invalid JSON fails open safely" bash -c "[ \"\$(printf 'keep text' | JUSTSAY_DICT_FILE='$T/bad.json' '$PP')\" = 'keep text' ]"
cat >"$T/nl.json" <<'D'
{"replacements": {"cmd": "rm -rf /\necho pwn"}}
D
check "dict output is re-sanitized (no newlines)" bash -c "out=\$(printf 'run cmd' | JUSTSAY_DICT_FILE='$T/nl.json' '$PP'); [[ \$out != *\$'\n'* && \$out = 'run rm -rf / echo pwn' ]]"

echo "# adapter (mock voxtype)"
mkdir -p "$T/mock"
cat >"$T/mock/voxtype" <<'M'
#!/bin/bash
echo "$*" >>"$MOCKLOG"
[ "$1" = status ] && { cat "$MOCKSTATE"; exit 0; }
exit 0
M
cat >"$T/mock/justsay" <<'M'
#!/bin/bash
[ "$1" = preflight ] && exit "${MOCK_PREFLIGHT:-0}"
M
printf '#!/bin/sh\nexit 0\n' >"$T/mock/notify-send"
chmod +x "$T/mock/"*
A="$ROOT/bin/omarchy-dictation-justsay"
run_ad() { # state action -> prints voxtype calls (except status)
  echo "$1" >"$T/st"; : >"$T/log"
  PATH="$T/mock:$PATH" MOCKSTATE="$T/st" MOCKLOG="$T/log" XDG_RUNTIME_DIR="$T" MOCK_PREFLIGHT="${3:-0}" "$A" "$2"
  grep -v '^status' "$T/log" | tr '\n' ';'
}
check "toggle from idle starts" bash -c "$(declare -f run_ad); T='$T' A='$A'; [ \"\$(run_ad idle toggle)\" = 'record start;' ]"
check "toggle while recording stops" bash -c "$(declare -f run_ad); T='$T' A='$A'; [ \"\$(run_ad recording toggle)\" = 'record stop;' ]"
check "toggle while transcribing does nothing" bash -c "$(declare -f run_ad); T='$T' A='$A'; [ -z \"\$(run_ad transcribing toggle)\" ]"
check "start while recording is ignored (no 2nd session)" bash -c "$(declare -f run_ad); T='$T' A='$A'; [ -z \"\$(run_ad recording start)\" ]"
check "stop when idle is a no-op" bash -c "$(declare -f run_ad); T='$T' A='$A'; [ -z \"\$(run_ad idle stop)\" ]"
check "failed preflight never records" bash -c "$(declare -f run_ad); T='$T' A='$A'; out=\$(run_ad idle toggle 1); [ -z \"\$out\" ]"
check "cancel while recording cancels" bash -c "$(declare -f run_ad); T='$T' A='$A'; [ \"\$(run_ad recording cancel)\" = 'record cancel;' ]"

echo "# plugin manifest"
if command -v omarchy-plugin-validate >/dev/null; then
  check "omarchy plugin validate" omarchy-plugin-validate "$ROOT"
else
  check "manifest is valid JSON" jq -e '.schemaVersion == 1 and .id == "justsay"' "$ROOT/manifest.json"
fi
check "bash syntax" bash -c "for f in '$ROOT'/bin/justsay '$ROOT'/bin/omarchy-*; do bash -n \"\$f\" || exit 1; done"

echo; echo "$pass passed, $fail failed"
(( fail == 0 ))
