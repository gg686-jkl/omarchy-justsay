# Just Say

[English](README.md) · **中文**

**面向 [Omarchy](https://omarchy.org) 的云端语音输入插件。** 按下快捷键直接说话，文字自动出现在光标处——直接复用你本机已有的 ChatGPT / Codex 登录态进行云端转写，支持中文、英文以及中英文混说（例如 `我刚刚 push 了一个 commit`），无需本地模型、无需 GPU、无需额外 API Key。

Just Say 直接接入 Omarchy 现有体系，不做侵入式改造：

- 注册为 **听写后端**（*Setup › Defaults › Dictation › Just Say (cloud)*），直接复用 Omarchy 原生快捷键（默认 **Alt+Space** 开关，**按住 Right Alt** 对讲）
- 可选 **顶栏状态组件**（Omarchy shell plugin），实时显示 ready / listening / transcribing / offline
- 复用系统已有的 **Voxtype** 负责录音、OSD 提示与文本输入，Just Say 仅将其 remote-Whisper 指向本地桥接服务

```
Alt+Space ─▶ omarchy-dictation ─▶ omarchy-dictation-justsay（前置健康检查、单会话互斥）
          ─▶ Voxtype（录音；whisper mode = remote）
          ─▶ http://127.0.0.1:8788  codex-asr 本地桥（用户级 systemd，仅回环 + 本地密钥）
          ─▶ chatgpt.com/backend-api/transcribe（非公开接口，复用本机 Codex 登录）
          ─▶ justsay-postprocess（字符清洗、可选自定义词表；无聚焦窗口时转剪贴板）
          ─▶ 单次输入到当前光标处，绝不按回车。
```

> [!WARNING]
> 云端转写通过 [codex-asr](https://github.com/Wangnov/codex-asr) 调用 OpenAI 的**非官方逆向接口**（`chatgpt.com/backend-api/transcribe`）。该接口随时可能变更、限流或失效，其使用受你的 ChatGPT 账号条款约束。若发生失败，Just Say 会明确弹窗提示，绝不会静默回退到本地模型或付费 API。

## 环境要求

- Omarchy 4.x 且已安装 **Voxtype**（*Install › AI › Dictation › Voxtype*）
- 已通过 Codex CLI 登录 ChatGPT（运行 `codex login`，确保 `~/.codex/auth.json` 存在）
- x86_64 或 aarch64 Linux，以及 `jq`、`curl`、`python3`（Omarchy 默认自带）

## 安装

以 Omarchy 插件方式安装（推荐）：

```bash
omarchy plugin add https://github.com/gg686-jkl/omarchy-justsay.git
~/.config/omarchy/plugins/justsay/install.sh
omarchy plugin enable justsay        # 可选：启用顶栏状态图标
```

或从 Git 克隆安装：

```bash
git clone https://github.com/gg686-jkl/omarchy-justsay.git && cd omarchy-justsay && ./install.sh
```

### 或者直接交给你的 AI Agent 自动安装

将以下提示词粘贴到运行在 Omarchy 机器上的 Claude Code、Codex 或其他终端 Agent：

```text
请在这台 Omarchy 机器上安装并配置 Just Say 云端语音输入（https://github.com/gg686-jkl/omarchy-justsay）。

1. 检查前置条件：Omarchy 4.x（存在 `omarchy-default-dictation`）、已安装 Voxtype 且
   `systemctl --user is-active voxtype` 为 active、已登录 Codex（`~/.codex/auth.json` 存在）。
   如缺少 Voxtype，请提示我先在 Omarchy 菜单 › Install › AI › Dictation › Voxtype 安装；
   如缺少登录，请提示我运行 `codex login` 后暂停等待。
   严禁读取、打印或复制 ~/.codex/ 里的任何内容。
2. 安装：执行 `omarchy plugin add https://github.com/gg686-jkl/omarchy-justsay.git --yes`
   （若已存在则执行 `omarchy plugin update justsay`），然后运行
   `~/.config/omarchy/plugins/justsay/install.sh`。
3. 验收：`justsay health` 必须输出 `ok: ready`；运行 `justsay doctor </dev/null` 并报告任何
   带 "!" 的异常行。若有失败，查看 `journalctl --user -u justsay-asr -u voxtype -n 50`
   修复后重新运行 install.sh（脚本幂等）。
4. 询问我是否需要启用顶栏图标（`omarchy plugin enable justsay`）。
5. 让我按 Alt+Space 试说一句话并再次按 Alt+Space 结束，确认文字正确输入。
6. 在我确认云端听写正常工作后，先展示 `justsay cleanup`（仅预览），征得同意后再运行
   `justsay cleanup --apply` 清理闲置的本地 Whisper 模型。
不要使用 sudo，不要修改 Hyprland 快捷键，也不要改动 Just Say 安装器管理范围之外的文件。
```

安装脚本完全**幂等**且**无需 root**（重复运行可修复配置，不会产生重复项）：

1. 自动备份 `~/.config/voxtype/config.toml`、Omarchy 菜单扩展文件与默认听写配置到 `~/.local/state/justsay/backups/`。
2. 下载 sha256 校验锁定的 `codex-asr v0.1.2` 到 `~/.local/share/justsay/bin/`。
3. 创建用户级 `justsay-asr.service`（仅监听 `127.0.0.1`，随机本地密钥存于权限 `0600` 的 `~/.config/justsay/server.env`）以及错误通知监听服务 `justsay-watch.service`。
4. 仅修改 Voxtype 的以下配置键：`whisper.mode = "remote"`、`remote_endpoint`、`language = "auto"`、`remote_send_auto_language = false`、`remote_timeout_secs = 60`、`auto_submit = false`、`text.smart_auto_submit = false`、`fallback_to_clipboard = true` 及 `[output.post_process]` 过滤器；并添加 systemd drop-in 注入密钥且将日志级别设为 `RUST_LOG=warn`（防止转写文本落入系统日志）。
5. 注册 Omarchy 菜单项并将 `justsay` 设为默认听写后端。

## 使用方式

| 操作 | 默认按键 |
|---|---|
| 开始 / 结束听写（切换模式） | **Alt+Space** |
| 按住说话 / 松开结束（对讲模式） | 按住 **Right Alt** |
| 取消本次录音 | 中键点击顶栏图标，或运行 `voxtype record cancel` |
| 运行诊断 | 右键点击顶栏图标，或运行 `justsay doctor` |

可通过 `justsay status`、`justsay health` 和 `justsay doctor` 查看实时状态与自检。

**安全特性**
- **单会话互斥**：转写进行中再次按键不会触发第二段录音，杜绝重复输入。
- **终端防误执行**：输出强制压平为单行，剥离换行、控制字符、ANSI/OSC 转义序列与双向文本控制符，且绝不模拟回车，在终端里语音输入**不可能意外执行命令**。
- **无聚焦窗口保护**：未检测到聚焦输入窗口时，自动写入剪贴板并弹窗提示，不盲打。
- **录音前预检**：开麦前自动检查本地桥、Codex 登录态（过期/缺失）与网络连通性，避免白说一段话。
- **明确报错、绝不静默降级**：桥接崩溃、超时、限流或上游报错时不会插入任何内容，并发送桌面通知说明原因；systemd 会自动拉起崩溃的本地桥。
- **无持久化录音/文本**：音频仅在内存中处理，Just Say 与 codex-asr 均不落盘保存录音或转写记录。

### 自定义词表（可选，推荐用于中英混说与专有名词）

如果某些技术名词或中英文混说词汇经常被 ASR 听错，可创建 `~/.config/justsay/dictionary.json`（修改后**立即生效，无需重启**）：

```json
{
  "replacements": {
    "vox type": "Voxtype",
    "codex asr": "codex-asr",
    "omarchy": "Omarchy"
  }
}
```

纯 ASCII 词条按英文词边界不区分大小写匹配；含中文/非 ASCII 词条按子串匹配。长词组优先于短词执行，替换结果会再次经过安全清洗，确保绝不引入换行或控制字符。

### 优化笔记本内置麦克风音质（可选）

浏览器和桌面聊天软件默认对麦克风启用 WebRTC 高通滤波（去直流偏置）、降噪（NS）和自动增益（AGC），而 Voxtype 直接采集原始 PCM。如果笔记本内置麦底噪偏大，或唤醒声卡瞬间存在直流爆音，可在 `~/.config/pipewire/pipewire.conf.d/60-justsay-webrtc-mic.conf` 添加一个 PipeWire WebRTC 虚拟输入源：

```hocon
context.modules = [
  {
    name = libpipewire-module-echo-cancel
    args = {
      library.name = "aec/libspa-aec-webrtc"
      monitor.mode = true
      audio.rate = 48000
      audio.channels = 1
      audio.position = [ MONO ]
      aec.args = {
        webrtc.high_pass_filter = true
        webrtc.noise_suppression = true
        webrtc.gain_control = true
      }
      capture.props = { node.name = "justsay-mic-capture", node.passive = true }
      source.props  = { node.name = "justsay-mic-clean", priority.session = 100 }
    }
  }
]
```

然后仅将 **Voxtype** 定向到该虚拟源（避免浏览器和聊天软件二次 WebRTC 处理）：在 `~/.config/justsay/server.env` 追加 `PIPEWIRE_NODE=justsay-mic-clean`，并重启 PipeWire 与 Voxtype：

```bash
systemctl --user restart pipewire pipewire-pulse wireplumber voxtype.service
```

如需更长的单次口述，也可以在 `~/.config/voxtype/config.toml` 中调大 `[audio] max_duration_secs`（默认 `60`，例如改为 `300`）并重启 `voxtype.service`。

## 清理闲置本地 Whisper 模型（可选）

确认云端听写工作正常后，可安全清理 Voxtype 之前下载的本地 Whisper 模型以释放磁盘空间：

```bash
justsay cleanup            # 预览模式：列出精确文件路径、大小与预计释放空间
justsay cleanup --apply    # 仅删除 ~/.local/share/voxtype/models/ggml-*.bin
```

该命令仅在云端模式激活且健康时才允许执行，不会触碰 Voxtype 配置、其他引擎模型、共享缓存或 `~/.codex/`。若日后需要恢复离线识别，运行 `voxtype setup --download` 即可重新下载模型。

## 切回本地、回滚与卸载

- **切回本地 Voxtype**：*Setup › Defaults › Dictation › Voxtype*，或运行 `justsay switch-to-voxtype`（精准还原 Just Say 改过的配置键）。
- **一键回滚**：`justsay rollback` 按字节恢复首次安装前的备份文件。
- **完全卸载**：*Remove › Dictation › Just Say*，或运行 `justsay uninstall`。会移除 systemd 服务、drop-in、密钥文件、菜单项与命令，并将默认听写后端切回 Voxtype；`~/.local/state/justsay/` 下的备份报告以及你可选创建的 `dictionary.json` 会予以保留。

## 常见问题排查

| 现象 | 解决方法 |
|---|---|
| 提示 "login expired" | 运行 `codex login`（或打开一次 Codex 刷新登录） |
| 提示 "cloud bridge is not running" | 运行 `systemctl --user restart justsay-asr`，再执行 `justsay doctor` |
| 没有打字，文字在剪贴板里 | 当前没有聚焦输入窗口，点进输入框粘贴即可 |
| 仅部分应用能输入 | Voxtype 默认使用 `wtype`，可查阅 Voxtype 文档切换 `dotool` 等输入驱动 |
| 查看日志 | `journalctl --user -u justsay-asr -u justsay-watch -u voxtype` |

## 开发与测试

```bash
tests/run.sh                         # 离线测试套件（配置编辑器、清洗与词表、适配器、插件清单）
tests/e2e.sh clip.wav "expected"     # 端到端实测：虚拟麦 → Voxtype → 云端 → 测试窗口
tests/e2e-terminal.sh clip.wav       # 终端安全实测：验证绝不向终端发送回车
```

实测脚本会打开独立测试窗口，一旦焦点移开会自动中止，绝不会向你的日常窗口误输入。

更多架构细节见 [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md)，第三方组件与致谢见 [THIRD_PARTY.md](THIRD_PARTY.md)。

## 许可证

MIT。Just Say 与 OpenAI、Omarchy/37signals 及 Voxtype 均无隶属关系。
