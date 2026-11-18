# Just Say

**Cloud dictation for [Omarchy](https://omarchy.org).** Press **Alt+Space** and speak. Your words appear at the cursor, transcribed in the cloud with the ChatGPT/Codex login you already have. Chinese, English and mixed speech (`我刚刚 push 了一个 commit`) all work. You don't need a local model, a GPU or an API key.

Just Say plugs into the parts of Omarchy that already exist:

- a **dictation backend** under *Setup › Defaults › Dictation › Just Say (cloud)*, so Omarchy's own shortcuts drive it: **Alt+Space** toggles and **holding Right Alt** is push-to-talk
- an optional **bar widget** (an Omarchy shell plugin) showing ready / listening / transcribing / offline
- your existing **Voxtype** for recording, its OSD and text insertion. Just Say only points Voxtype's remote-Whisper backend at a local bridge.

```
Alt+Space ─▶ omarchy-dictation ─▶ omarchy-dictation-justsay (preflight, single session)
          ─▶ Voxtype (records; whisper mode = remote)
          ─▶ http://127.0.0.1:8788  codex-asr bridge (user systemd, loopback + local key)
          ─▶ chatgpt.com/backend-api/transcribe   (unofficial, uses your Codex login)
          ─▶ justsay-postprocess (strips newlines/control chars; clipboard if no focus)
          ─▶ typed once into the focused window. Enter is never pressed.
```

> [!WARNING]
> Transcription goes through an **unofficial, reverse-engineered** ChatGPT endpoint, by way of [codex-asr](https://github.com/Wangnov/codex-asr). It may change, rate-limit or stop working at any time, and its use falls under your ChatGPT account's terms. When it fails, Just Say tells you. It never quietly falls back to a local model or a paid API.

## Requirements

- Omarchy 4.x with **Voxtype** installed (*Install › AI › Dictation › Voxtype*)
- A ChatGPT login for the Codex CLI (`codex login`; `~/.codex/auth.json` must exist)
- x86_64 or aarch64 Linux, plus `jq`, `curl` and `python3` (Omarchy already ships them)

## Install

As an Omarchy plugin (recommended):

```bash
omarchy plugin add https://github.com/gg686-jkl/omarchy-justsay.git
~/.config/omarchy/plugins/justsay/install.sh
omarchy plugin enable justsay        # optional bar widget
```

Or from a clone:

```bash
git clone https://github.com/gg686-jkl/omarchy-justsay.git && cd omarchy-justsay && ./install.sh
```

### Or let your AI agent do it

Paste this into Claude Code, Codex or any terminal agent running on your Omarchy machine:

```text
Set up Just Say cloud dictation (https://github.com/gg686-jkl/omarchy-justsay) on this Omarchy machine.

1. Check prerequisites: Omarchy 4.x (`omarchy-default-dictation` exists), Voxtype installed and
   `systemctl --user is-active voxtype` is active, and a Codex login (`~/.codex/auth.json` exists).
   If Voxtype is missing, tell me to install it from Omarchy menu › Install › AI › Dictation › Voxtype.
   If the login is missing, tell me to run `codex login`, then stop and wait for me.
   Never read, print or copy the contents of ~/.codex/.
2. Install: `omarchy plugin add https://github.com/gg686-jkl/omarchy-justsay.git --yes`
   (if it already exists, run `omarchy plugin update justsay`), then run
   `~/.config/omarchy/plugins/justsay/install.sh`.
3. Verify: `justsay health` must print `ok: ready`. Run `justsay doctor </dev/null` and report any
   line marked "!". If something fails, read `journalctl --user -u justsay-asr -u voxtype -n 50`
   and fix it, then run install.sh again (it's idempotent).
4. Ask me whether to enable the bar widget (`omarchy plugin enable justsay`).
5. Ask me to press Alt+Space, say a sentence, press Alt+Space again, and confirm the text appeared.
6. Only after I confirm dictation works, show me `justsay cleanup` (a dry run) and ask before running
   `justsay cleanup --apply` to delete the unused local Whisper model.
Don't use sudo, don't edit Hyprland bindings, and don't touch anything outside what Just Say's installer manages.
```

The installer is idempotent: running it again repairs the setup and never duplicates anything. It works entirely as your user, with no root:

1. Backs up `~/.config/voxtype/config.toml`, the Omarchy menu extension file and the dictation default to `~/.local/state/justsay/backups/`.
2. Downloads codex-asr v0.1.2 from its GitHub release (sha256-pinned) into `~/.local/share/justsay/bin/`.
3. Creates `justsay-asr.service`, which listens on 127.0.0.1 only and needs a random local key stored in `~/.config/justsay/server.env` (mode 0600). It also creates `justsay-watch.service`, which turns transcription errors into notifications.
4. Changes only these Voxtype keys: `whisper.mode = "remote"`, `remote_endpoint`, `language = "auto"`, `remote_timeout_secs`, `auto_submit = false`, `fallback_to_clipboard = true`, plus an `[output.post_process]` filter. It also adds a drop-in that hands Voxtype the key and keeps transcripts out of the journal.
5. Adds the menu entries and selects `justsay` as Omarchy's dictation backend.

## Use

| Action | Keys |
|---|---|
| Start / finish dictation | **Alt+Space** |
| Push-to-talk | hold **Right Alt** |
| Cancel | middle-click the bar widget, or `voxtype record cancel` |
| Diagnostics | right-click the widget, or `justsay doctor` |

`justsay status`, `justsay health` and `justsay doctor` show what's going on.

**Safety behavior**
- Only one session runs at a time. Pressing the key while a transcription is in flight does nothing, so text can't be inserted twice.
- Text comes out as a single line. Newlines, control characters, escape sequences and bidi overrides are stripped, and Enter is never pressed, so dictating into a terminal **can't run a command**.
- With no focused window, the text goes to the clipboard and you get a notification instead of typed text.
- Before recording starts, Just Say checks the bridge, your Codex login (expired or missing) and the network, so you aren't left talking into nothing.
- A bridge crash, timeout, rate limit or upstream error means nothing is inserted and a notification explains why. systemd restarts a crashed bridge.
- Audio stays in memory, and neither Just Say nor codex-asr stores audio or transcripts.

## Freeing the local model (optional)

Once cloud dictation works for you, the Whisper model Voxtype downloaded is unused:

```bash
justsay cleanup            # dry run: exact files, sizes, expected savings
justsay cleanup --apply    # deletes only ~/.local/share/voxtype/models/ggml-*.bin
```

The command refuses to run unless cloud mode is active and healthy. It touches nothing else: no Voxtype config, other engines' models, shared caches or `~/.codex/`. To go back to offline dictation you'll have to download the model again with `voxtype setup --download`.

## Switching back, rollback and uninstall

- **Back to local Voxtype:** *Setup › Defaults › Dictation › Voxtype*, or `justsay switch-to-voxtype`. This restores exactly the Voxtype keys Just Say changed.
- **Rollback:** `justsay rollback` restores the backed-up files byte-for-byte.
- **Uninstall:** *Remove › Dictation › Just Say*, or `justsay uninstall`. This removes the services, drop-in, key file, menu entries and commands, and makes Voxtype the default backend again. Backups and reports stay in `~/.local/state/justsay/`.

## Troubleshooting

| Symptom | Fix |
|---|---|
| "login expired" | run `codex login` (or open Codex once) |
| "cloud bridge is not running" | `systemctl --user restart justsay-asr`, then `justsay doctor` |
| nothing typed, text on the clipboard | no window had focus. Click into the input and paste. |
| works in some apps only | Voxtype types with `wtype`. See Voxtype's docs for `dotool` and other drivers. |
| logs | `journalctl --user -u justsay-asr -u justsay-watch -u voxtype` |

## Development

```bash
tests/run.sh                         # offline suite (editors, sanitizer, adapter, manifest)
tests/e2e.sh clip.wav "expected"     # live: virtual mic → Voxtype → cloud → test window
tests/e2e-terminal.sh clip.wav       # live: verifies a terminal never receives Enter
```

The live tests open their own window and abort if focus moves away, so they never type into your apps.

See [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) for the design, and [THIRD_PARTY.md](THIRD_PARTY.md) for attributions.

## License

MIT. Just Say is not affiliated with OpenAI, Omarchy/37signals or Voxtype.
