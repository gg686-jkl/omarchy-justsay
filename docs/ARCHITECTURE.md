# Architecture

## Components

| Piece | Where it lives once installed | Role |
|---|---|---|
| `omarchy-dictation-justsay` | `~/.local/bin` (symlink) | Omarchy dictation-backend adapter. `omarchy-dictation` calls it from Alt+Space and Right Alt. It serializes presses with a flock, refuses to start when preflight fails, and ignores presses while Voxtype is `recording` or `transcribing`. |
| `justsay` | `~/.local/bin` (symlink) | CLI: install, activate, deactivate, health, preflight, doctor, watch, cleanup, rollback, uninstall. |
| `justsay-asr.service` | `~/.config/systemd/user` | Runs `codex-asr serve` on 127.0.0.1 only, with a local bearer key read from an env file (never on the command line) and systemd hardening. |
| `justsay-watch.service` | `~/.config/systemd/user` | Follows Voxtype's journal for `Transcription failed` and maps each one to a notification. It keeps the last error in `$XDG_RUNTIME_DIR`, which is never persisted. |
| `voxtype.service.d/justsay.conf` | drop-in | Loads `~/.config/justsay/server.env` (handing Voxtype `VOXTYPE_WHISPER_API_KEY` and any optional overrides such as `PIPEWIRE_NODE`), sets `RUST_LOG=warn` so transcripts never reach the journal, and pulls in the two services above. |
| `justsay-postprocess` | Voxtype `[output.post_process]` | Reads the transcript on stdin, applies optional `~/.config/justsay/dictionary.json` replacements, re-sanitizes to a single line, and writes to stdout. With no focused window it uses the clipboard, prints nothing and sends a notification. |
| `Widget.qml` + `manifest.json` | Omarchy shell plugin `justsay` | Bar icon. It watches Voxtype's state file (inotify) and polls `justsay health --json`. |
| menu rows | `~/.config/omarchy/extensions/omarchy-menu.jsonc`, between markers | *Setup › Defaults › Dictation › Just Say (cloud)*, *Remove › Dictation › Just Say*. They also override the Voxtype row so that picking Voxtype restores local settings first. |

## Why these choices

- **Reuse Voxtype instead of replacing it.** Voxtype already handles recording, the OSD, `wtype` injection with clipboard fallback, modifier-release waiting and cancellation. Its remote Whisper mode speaks the OpenAI `/v1/audio/transcriptions` shape, which codex-asr serves.
- **Use the backend interface instead of new keybindings.** Omarchy binds Alt+Space and Right Alt to `omarchy-dictation`, which dispatches to `omarchy-dictation-<backend>`. Selecting the `justsay` backend reuses those bindings, so no Hyprland config changes.
- **Edit keys instead of replacing the config.** `justsay-edit` changes individual `key = value` lines in exact TOML sections and records each original value, so deactivating restores only what Just Say changed, even after you've edited other settings.
- **Language `auto`.** Voxtype's remote mode ignores language arrays and uses only the first entry. Leaving the language out lets the upstream detect zh, en and code-switched speech.
- **No silent fallback.** If the bridge or upstream fails, Voxtype reports an error and inserts nothing. Just Say never switches to a local model or a paid API.

## Failure matrix (verified on Omarchy 4.5 / Voxtype 1.1.1 / codex-asr 0.1.2)

| Condition | What happens |
|---|---|
| Bridge stopped before recording | Preflight refuses to record and you get a notification. |
| Bridge killed mid-recording | Voxtype logs `Connection refused`, nothing is inserted, and the watcher sends a notification. systemd restarts the bridge. |
| Codex token expired or missing | Preflight refuses and asks you to run `codex login`. An upstream 401 turns into a notification. |
| Upstream unreachable or offline | codex-asr returns 502, nothing is inserted, and you get a notification. Preflight also checks for a default route. |
| Wrong or missing local key | 401 from the bridge, and `justsay doctor` flags it. |
| No speech or empty result | Nothing is typed. |
| No focused window | Text goes to the clipboard and you get a notification. |
| Key pressed during transcription | Ignored, with a notification. |
| Text containing newlines or escapes | Flattened to one line, with control characters stripped. |
