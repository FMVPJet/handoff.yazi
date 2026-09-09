-- ~/.config/yazi/plugins/handoff.yazi/config.lua
-- Add or update your app mappings here.

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
		-- To add a new app, append another entry like this:
		-- i = "Messages",
	},

	-- Advanced options (optional)
	-- cache_dir = "/tmp/handoff-swift-cache",
	-- archive_dir = "/tmp/handoff-archive",
	-- archive_cleanup_minutes = 1440,  -- 24 hours
	-- airdrop_timeout_seconds = 300,   -- 5 minutes
}
