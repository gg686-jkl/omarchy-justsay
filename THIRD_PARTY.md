# Third-party components

Just Say contains no third-party code. The installer downloads or uses these
projects at install time; nothing from them is redistributed in this repo.

| Component | License | How it's used |
|---|---|---|
| [Voxtype](https://github.com/peteonrails/voxtype) | MIT | Already installed by Omarchy. Just Say only changes a few keys in `~/.config/voxtype/config.toml` and adds a systemd drop-in. |
| [codex-asr](https://github.com/Wangnov/codex-asr) v0.1.2 | MIT | Downloaded from its GitHub release, sha256-pinned, into `~/.local/share/justsay/bin/`. Its license is saved next to it. |
| [Omarchy](https://github.com/basecamp/omarchy) | MIT | Host desktop. Just Say uses its documented dictation-backend, menu-extension and shell-plugin interfaces. |

codex-asr talks to `chatgpt.com/backend-api/transcribe`, the **unofficial** endpoint
the Codex desktop app uses for dictation. That service belongs to OpenAI and
falls under your ChatGPT account's terms. Just Say neither bundles nor shares
any credentials.
