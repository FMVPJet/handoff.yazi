# handoff.yazi

A macOS-focused file handoff toolkit for [Yazi](https://github.com/sxyazi/yazi).

`handoff.yazi` collects the file actions that usually happen after browsing: copying files as macOS file objects, archiving, sharing to apps, syncing to remote hosts, and opening items with the right tool.

## Highlights

- Copy selected items as native macOS file objects
- Archive items and copy the resulting zip file
- Share files to macOS apps, including AirDrop
- Upload files with `rsync` through an interactive remote picker
- Open directories in Finder, VS Code, or Cursor
- Search installed macOS apps with `Open With...`

## What It Does

- `Copy`
  - Copies selected items as file objects, so they can be pasted into Finder and compatible apps
- `Archive`
  - Creates a zip archive from selected items and copies the archive as a file object
- `Share`
  - Shares selected items to apps such as AirDrop, WeChat, Feishu, Slack, and others
- `Remote Sync`
  - Uploads selected items to a remote host with `rsync`
  - Remembers the last successful host and destination
  - Copies the uploaded remote path after a successful sync
- `Open`
  - Opens the current directory in Finder, VS Code, or Cursor
  - Includes a dynamic `Open With...` picker for installed macOS apps

## Requirements

- macOS
- [Yazi](https://github.com/sxyazi/yazi)
- `swift`
- `ssh`
- `rsync`
- `fzf`
- `zsh`

## Installation

Clone the repository into your Yazi plugins directory:

```sh
git clone git@github.com:FMVPJet/handoff.yazi.git \
  ~/.config/yazi/plugins/handoff.yazi
```

Or, once the repository is published in a package-friendly layout, install it with:

```sh
ya pkg add FMVPJet/handoff
```

Add these key bindings to `~/.config/yazi/keymap.toml`:

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

## Quick Start

1. Open Yazi on macOS.
2. Press `\`.
3. Choose one of the handoff actions:
   - `c` to copy
   - `z` to archive
   - `s` to share
   - `r` to sync remotely
   - `of` / `ov` / `oc` / `oo` to open with apps

## Configuration

Edit `config.lua` to add or remove share targets:

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

Edit `remote_sync.env.sh` to override environment-dependent remote sync defaults.

### Configuration Split

- Use `config.lua` for plugin-facing settings such as share targets
- Use `remote_sync.env.sh` for shell/runtime settings used by `Remote Sync`

This keeps the Lua plugin layer and the shell sync layer decoupled while still giving each of them a clear configuration entry point.

## Usage

Press `\` in Yazi, then use one of the following actions:

| Key | Action | Description |
| --- | --- | --- |
| `c` | Copy | Copy the selected items as file objects |
| `z` | Archive | Create an archive and copy it |
| `s` | Share | Share the selected items to an app |
| `r` | Remote Sync | Upload the selected items to a remote host |
| `of` | Open in Finder | Open the current directory in Finder |
| `ov` | Open in VS Code | Open the current directory in VS Code |
| `oc` | Open in Cursor | Open the current directory in Cursor |
| `oo` | Open With... | Choose an installed app with `fzf` |

### Share

- AirDrop uses the original selected items
- Non-AirDrop apps automatically receive a zip archive when directories are included

### Remote Sync

- Uses `fzf` to choose a host and browse the remote destination
- Remembers the last successful host and destination
- Copies the uploaded remote path to the clipboard after a successful sync
- Reads `Host` entries from the top-level `~/.ssh/config` file only
- `Include` directives are not expanded yet

### Open With

- Uses `fzf` to search installed macOS applications
- Tries Spotlight first and falls back to scanning common app folders
- Remembers the most recently used app and moves it to the top of the list
- Opens the selected items with the chosen app, similar to Finder's `Open With`

## Debugging

`Remote Sync` logging is off by default.

To enable debug logging:

```sh
HANDOFF_REMOTE_SYNC_DEBUG=1 yazi
```

When enabled, logs are written to:

```text
/tmp/handoff-remote-sync-debug.log
```

### Remote Sync Environment Overrides

`Remote Sync` uses dynamic defaults and can also be overridden with environment variables:

- `HANDOFF_HOME`
  - Override the home directory used by the script
- `HANDOFF_SSH_CONFIG_PATH`
  - Override the SSH config file path
- `HANDOFF_STATE_ROOT`
  - Override the root directory used for saved sync state
- `HANDOFF_REMOTE_SYNC_DEBUG_LOG`
  - Override the debug log file path

The recommended place to set these values is `remote_sync.env.sh`.

Legacy `SMART_ACTION_*` environment variables are still accepted for backward compatibility during migration.

## Limitations

- macOS-oriented implementation
- Remote Sync currently reads only top-level `~/.ssh/config` host entries
- Sharing and clipboard behavior are designed for macOS app workflows

## Suggested GitHub Extras

- Add a short GIF for `Remote Sync`
- Add a short GIF for `Open With...`
- Add repository topics such as `yazi`, `yazi-plugin`, `macos`, `clipboard`, and `rsync`

## License

[MIT](./LICENSE)
