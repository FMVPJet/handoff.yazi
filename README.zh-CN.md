[English](./README.md) | 简体中文

# handoff.yazi

一个面向 macOS 的 [Yazi](https://github.com/sxyazi/yazi) 文件交接工具包。

`handoff.yazi` 把浏览之后最常发生的动作收拢到一起：把文件作为 macOS 文件对象复制、压缩归档、分享到应用、同步到远端主机，以及用合适的应用打开当前内容。

## 特性亮点

- 将选中项作为原生 macOS 文件对象复制
- 压缩选中项并复制生成的 zip 文件
- 分享文件到 macOS 应用，包括 AirDrop
- 通过交互式远端选择器使用 `rsync` 上传
- 在 Finder、VS Code 或 Cursor 中打开当前目录
- 使用动态 `Open With...` 搜索本机已安装应用

## 它能做什么

- `Copy`
  - 将选中项复制为文件对象，可以直接粘贴到 Finder 和兼容应用中
- `Archive`
  - 为选中项创建 zip 压缩包，并将压缩包作为文件对象复制
- `Share`
  - 将选中项分享到 AirDrop、微信、飞书、Slack 等应用
- `Remote Sync`
  - 使用 `rsync` 把选中项上传到远程主机
  - 记住上一次成功的主机和目标目录
  - 上传成功后自动复制远端路径
- `Open`
  - 在 Finder、VS Code、Cursor 中打开当前目录
  - 提供一个面向已安装应用的动态 `Open With...` 选择器

## 依赖

- macOS
- [Yazi](https://github.com/sxyazi/yazi)
- `swift`
- `ssh`
- `rsync`
- `fzf`
- `zsh`

## 安装

把仓库克隆到 Yazi 的插件目录：

```sh
git clone git@github.com:FMVPJet/handoff.yazi.git \
  ~/.config/yazi/plugins/handoff.yazi
```

或者在支持包管理布局时，使用：

```sh
ya pkg add FMVPJet/handoff
```

然后在 `~/.config/yazi/keymap.toml` 中加入这些绑定：

```toml
[[mgr.prepend_keymap]]
on   = [ "\\", "c" ]
run  = "plugin handoff -- copy_file"
desc = "Copy"

[[mgr.prepend_keymap]]
on   = [ "\\", "z" ]
run  = "plugin handoff -- smart_zip"
desc = "Archive"

[[mgr.prepend_keymap]]
on   = [ "\\", "s" ]
run  = "plugin handoff -- share_menu"
desc = "Share"

[[mgr.prepend_keymap]]
on   = [ "\\", "r" ]
run  = "shell '. \"$HOME/.config/yazi/plugins/handoff.yazi/remote_sync.env.sh\" 2>/dev/null || true; /bin/zsh -f \"$HOME/.config/yazi/plugins/handoff.yazi/remote_sync.zsh\" %h %s' --block"
desc = "Remote Sync"

[[mgr.prepend_keymap]]
on   = [ "\\", "o", "f" ]
run  = "plugin handoff -- open_finder"
desc = "Open in Finder"

[[mgr.prepend_keymap]]
on   = [ "\\", "o", "v" ]
run  = "plugin handoff -- open_vscode"
desc = "Open in VS Code"

[[mgr.prepend_keymap]]
on   = [ "\\", "o", "c" ]
run  = "plugin handoff -- open_cursor"
desc = "Open in Cursor"

[[mgr.prepend_keymap]]
on   = [ "\\", "o", "o" ]
run  = "shell '/bin/zsh -f \"$HOME/.config/yazi/plugins/handoff.yazi/open_with.zsh\" %h %s' --block"
desc = "Open With..."
```

## 快速开始

1. 在 macOS 上打开 Yazi。
2. 按 `\`。
3. 选择一个交接动作：
   - `c` 复制
   - `z` 压缩
   - `s` 分享
   - `r` 远程同步
   - `of` / `ov` / `oc` / `oo` 用应用打开

## 配置

编辑 `config.lua` 来添加或删除分享目标：

```lua
return {
	share_apps = {
		w = "WeChat",
		f = "Feishu",
		d = "DingTalk",
		t = "Telegram",
		m = "Mail",
		s = "Slack",
		n = "Notes",
		e = "Evernote",
	},
}
```

编辑 `remote_sync.env.sh` 来覆盖依赖环境的远程同步默认值。

### 配置分层

- `config.lua` 用来管理插件层配置，例如分享目标
- `remote_sync.env.sh` 用来管理 `Remote Sync` 的 shell / 运行时配置

这样可以把 Lua 插件层和 shell 同步层清晰拆开，同时保留明确的配置入口。

## 使用说明

在 Yazi 中按 `\`，然后使用下面这些动作：

| 键位 | 动作 | 说明 |
| --- | --- | --- |
| `c` | Copy | 将选中项复制为文件对象 |
| `z` | Archive | 创建压缩包并复制 |
| `s` | Share | 把选中项分享到应用 |
| `r` | Remote Sync | 上传选中项到远程主机 |
| `of` | Open in Finder | 在 Finder 中打开当前目录 |
| `ov` | Open in VS Code | 在 VS Code 中打开当前目录 |
| `oc` | Open in Cursor | 在 Cursor 中打开当前目录 |
| `oo` | Open With... | 使用 `fzf` 选择已安装应用 |

### Share

- AirDrop 会直接使用原始选中项
- 非 AirDrop 应用在包含目录时会自动收到 zip 压缩包

### Remote Sync

- 使用 `fzf` 选择主机并浏览远程目标目录
- 记住上一次成功的主机和目录
- 上传成功后自动把远端路径复制到剪贴板
- 目前只读取顶层 `~/.ssh/config` 中的 `Host`
- 暂不展开 `Include`

### Open With

- 使用 `fzf` 搜索已安装的 macOS 应用
- 优先尝试 Spotlight，不行再回退到常见 app 目录扫描
- 会记住最近一次使用的应用，并放到列表最前
- 行为类似 Finder 的 `Open With`

## 调试

`Remote Sync` 默认关闭调试日志。

如需开启：

```sh
HANDOFF_REMOTE_SYNC_DEBUG=1 yazi
```

开启后日志默认写到：

```text
/tmp/handoff-remote-sync-debug.log
```

### Remote Sync 环境变量覆盖

`Remote Sync` 采用动态默认值，也可以通过环境变量覆盖：

- `HANDOFF_HOME`
  - 覆盖脚本使用的 home 目录
- `HANDOFF_SSH_CONFIG_PATH`
  - 覆盖 SSH 配置文件路径
- `HANDOFF_STATE_ROOT`
  - 覆盖保存同步状态的根目录
- `HANDOFF_REMOTE_SYNC_DEBUG_LOG`
  - 覆盖调试日志文件路径

建议把这些值写进 `remote_sync.env.sh`。

为了迁移兼容，旧的 `SMART_ACTION_*` 环境变量仍然可用。

## 限制

- 当前实现偏向 macOS
- `Remote Sync` 目前只读取顶层 `~/.ssh/config` 中的 host
- 分享和剪贴板行为主要围绕 macOS 应用工作流设计

## 建议补充到 GitHub 的内容

- 加一个 `Remote Sync` 的短 GIF
- 加一个 `Open With...` 的短 GIF
- 添加 `yazi`、`yazi-plugin`、`macos`、`clipboard`、`rsync` 等 topics

## License

[MIT](./LICENSE)
