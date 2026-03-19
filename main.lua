-- ~/.config/yazi/plugins/handoff.yazi/main.lua

-- 1. Load external config (optional)
local config = { share_apps = { w = "WeChat", f = "Feishu" } }
local ok, custom_config = pcall(require, "handoff.config")
if not ok then
	ok, custom_config = pcall(require, "smart-action.config")
end
if ok then config = custom_config end

local TITLE = "Handoff"
local AIRDROP_LABEL = "AirDrop"
local SWIFT_CACHE_DIR = "/tmp/handoff-swift-cache"
local SWIFT_ENV_PREFIX = table.concat({
	"SWIFT_MODULE_CACHE_PATH=/tmp/swift-module-cache",
	"CLANG_MODULE_CACHE_PATH=/tmp/clang-module-cache",
}, " ")

local function shell_escape(value)
	return "'" .. tostring(value):gsub("'", "'\"'\"'") .. "'"
end

local function command_succeeded(ok, _, code)
	if type(ok) == "number" then return ok == 0 end
	if code ~= nil then return ok == true and code == 0 end
	return ok == true
end

local function run_command(cmd)
	local ok_run, why, code = os.execute(cmd)
	return command_succeeded(ok_run, why, code)
end

local function run_command_capture(cmd)
	local handle = io.popen(cmd .. " 2>&1")
	if not handle then return false, "Failed to start command", nil end
	local output = handle:read("*a") or ""
	local ok_close, why, code = handle:close()
	return command_succeeded(ok_close, why, code), output, code
end

local function notify(level, content, title, timeout)
	ya.notify({
		title = title or TITLE,
		content = content,
		level = level,
		timeout = timeout or 3,
	})
end

local function notify_error(content, title, timeout)
	notify("error", content, title, timeout)
end

local function notify_warn(content, title, timeout)
	notify("warn", content, title, timeout)
end

local function run_command_or_notify(cmd, failure_content, title)
	if run_command(cmd) then return true end
	notify_error(failure_content, title)
	return false
end

local function write_temp_file(prefix, suffix, content)
	local path = string.format("/tmp/%s-%d-%06d%s", prefix, os.time(), math.random(0, 999999), suffix or "")
	local file = io.open(path, "w")
	if not file then return nil end
	file:write(content)
	file:close()
	return path
end

local function file_exists(path)
	local file = io.open(path, "rb")
	if not file then return false end
	file:close()
	return true
end

local function hash_source(source)
	local hash = 5381
	for i = 1, #source do
		hash = (hash * 33 + source:byte(i)) % 4294967296
	end
	return string.format("%08x-%d", hash, #source)
end

local function ensure_swift_binary(source)
	if not run_command("mkdir -p " .. shell_escape(SWIFT_CACHE_DIR)) then
		return nil
	end

	local cache_key = hash_source(source)
	local script_path = SWIFT_CACHE_DIR .. "/" .. cache_key .. ".swift"
	local binary_path = SWIFT_CACHE_DIR .. "/" .. cache_key

	if file_exists(binary_path) then
		return binary_path
	end

	if not file_exists(script_path) then
		local script_file = io.open(script_path, "w")
		if not script_file then return nil end
		script_file:write(source)
		script_file:close()
	end

	local compile_cmd = table.concat({
		SWIFT_ENV_PREFIX,
		"swiftc -O",
		shell_escape(script_path),
		"-o",
		shell_escape(binary_path),
		"> /dev/null 2>&1",
	}, " ")

	if run_command(compile_cmd) and file_exists(binary_path) then
		return binary_path
	end

	os.remove(binary_path)
	return nil
end

local function run_swift_script(source, args)
	local executable_path = ensure_swift_binary(source)
	local script_path = nil
	local cmd = nil

	if executable_path then
		cmd = table.concat({
			SWIFT_ENV_PREFIX,
			shell_escape(executable_path),
		}, " ")
	else
		script_path = write_temp_file("handoff", ".swift", source)
		if not script_path then return false end
		cmd = table.concat({
			SWIFT_ENV_PREFIX,
			"swift",
			shell_escape(script_path),
		}, " ")
	end

	for _, arg in ipairs(args or {}) do
		cmd = cmd .. " " .. shell_escape(arg)
	end
	cmd = cmd .. " > /dev/null 2>&1"

	local ok_exec = run_command(cmd)
	if script_path then
		os.remove(script_path)
	end
	return ok_exec
end

-- 2. Data helpers (CWD & selected items)
local get_cwd = ya.sync(function() return tostring(cx.active.current.cwd) end)
local get_selected_urls = ya.sync(function()
	local urls = {}
	for _, u in pairs(cx.active.selected) do table.insert(urls, tostring(u)) end
	if #urls == 0 then
		local h = cx.active.current.hovered
		if h then table.insert(urls, tostring(h.url)) end
	end
	return urls
end)

-- 3. Shared file helpers
local function is_directory(path)
	return run_command("test -d " .. shell_escape(path))
end

local function any_directory(urls)
	for _, u in ipairs(urls) do
		if is_directory(u) then return true end
	end
	return false
end

local function get_selected_urls_or_notify()
	local urls = get_selected_urls()
	if #urls == 0 then
		notify_warn("Select one or more items first.")
		return nil
	end
	return urls
end

-- 4. Swift clipboard helpers
local function set_clipboard_files_swift(file_list)
	return run_swift_script([[
		import AppKit
		import Foundation
		let pb = NSPasteboard.general
		pb.clearContents()
		let fm = FileManager.default
		let urls = CommandLine.arguments.dropFirst().map { path -> NSURL in
			var isDir = ObjCBool(false)
			fm.fileExists(atPath: path, isDirectory: &isDir)
			return URL(fileURLWithPath: path, isDirectory: isDir.boolValue) as NSURL
		}
		let paths = Array(CommandLine.arguments.dropFirst())
		let fileNamesType = NSPasteboard.PasteboardType(rawValue: "NSFilenamesPboardType")

		var ok = pb.writeObjects(Array(urls))
		ok = pb.setPropertyList(paths, forType: fileNamesType) || ok

		if paths.count == 1, let first = urls.first as URL? {
			ok = pb.setString(first.absoluteString, forType: .fileURL) || ok
		}

		if !ok { exit(1) }
	]], file_list)
end

local function copy_file_objects(urls, failure_context)
	if set_clipboard_files_swift(urls) then return true end
	notify_error(failure_context or "Couldn't copy the selected items to the clipboard.")
	return false
end

local function share_via_airdrop_swift(file_list)
	return run_swift_script([[
		import AppKit
		import Foundation

		final class AirDropDelegate: NSObject, NSSharingServiceDelegate {
			private let app: NSApplication
			private var didFinish = false

			init(app: NSApplication) {
				self.app = app
			}

			private func finish() {
				guard !didFinish else { return }
				didFinish = true
				app.stop(nil)
			}

			func sharingService(_ sharingService: NSSharingService, didShareItems items: [Any]) {
				finish()
			}

			func sharingService(_ sharingService: NSSharingService, didFailToShareItems items: [Any], error: any Error) {
				finish()
			}
		}

		let urls = CommandLine.arguments.dropFirst().map { URL(fileURLWithPath: $0) }
		guard !urls.isEmpty else { exit(1) }

		let app = NSApplication.shared
		app.setActivationPolicy(.accessory)
		app.activate(ignoringOtherApps: true)

		let items: [Any] = urls
		var service = NSSharingService(named: .sendViaAirDrop)
		if service == nil {
			service = NSSharingService.sharingServices(forItems: items).first(where: { $0.title.localizedCaseInsensitiveContains("AirDrop") })
		}

		guard let service else { exit(2) }
		guard service.canPerform(withItems: items) else { exit(3) }

		let delegate = AirDropDelegate(app: app)
		service.delegate = delegate

		Timer.scheduledTimer(withTimeInterval: 300, repeats: false) { _ in
			app.stop(nil)
		}

		service.perform(withItems: items)
		app.run()
	]], file_list)
end

local function share_via_airdrop(urls)
	if share_via_airdrop_swift(urls) then
		return true
	end

	if not open_airdrop_finder(urls) then
		notify_error("Couldn't share the selected items via AirDrop.")
		return false
	end

	notify_warn("Native AirDrop wasn't available. Opened Finder AirDrop instead.", TITLE, 4)
	return true
end

local function open_airdrop_finder(urls)
	for _, u in ipairs(urls) do
		if not run_command("open -a " .. shell_escape(AIRDROP_LABEL) .. " " .. shell_escape(u)) then
			return false
		end
	end
	return true
end

local ZIP_TEMP_DIR = "/tmp/handoff-archive"

local function trim_output(output, max_len)
	output = tostring(output or ""):gsub("%s+$", "")
	if output == "" then return output end
	max_len = max_len or 240
	if #output <= max_len then return output end
	return output:sub(1, max_len - 1) .. "…"
end

local function ensure_zip_temp_dir()
	if run_command("mkdir -p " .. shell_escape(ZIP_TEMP_DIR)) then return true end
	notify_error("Couldn't create the temporary archive folder.", TITLE, 6)
	return false
end

local function cleanup_old_zip_artifacts()
	run_command(
		"find " .. shell_escape(ZIP_TEMP_DIR)
			.. " -type f -name '*_[0-1][0-9][0-3][0-9]_[0-2][0-9][0-5][0-9].zip'"
			.. " -mmin +1440 -delete > /dev/null 2>&1"
	)
end

local function build_zip_name(urls)
	local base_name = "Archive"
	if #urls == 1 then
		base_name = (urls[1]:match("([^/]+)/*$") or "Archive"):gsub("%s+", "_")
	end
	return string.format("%s/%s_%s.zip", ZIP_TEMP_DIR, base_name, os.date("%m%d_%H%M"))
end

local function notify_zip_failure(output, code)
	local detail = trim_output(output)
	if detail ~= "" then
		notify_error("Couldn't create the archive:\n" .. detail, TITLE, 6)
	else
		notify_error("Couldn't create the archive (exit code: " .. tostring(code or "?") .. ").", TITLE, 6)
	end
	return false
end

local function create_zip_file(urls)
	if #urls == 0 then return false end
	if not ensure_zip_temp_dir() then return false end

	local zip_name = build_zip_name(urls)
	
	local ok_zip, zip_output, zip_code = false, "", nil
	if #urls == 1 then
		if is_directory(urls[1]) then
			ok_zip, zip_output, zip_code = run_command_capture(
				"ditto -c -k --sequesterRsrc --keepParent "
					.. shell_escape(urls[1]) .. " " .. shell_escape(zip_name)
			)
		else
			local parent_dir = urls[1]:match("^(.*)/[^/]+/*$") or "."
			local file_name = urls[1]:match("([^/]+)/*$") or ""
			ok_zip, zip_output, zip_code = run_command_capture(
				"cd " .. shell_escape(parent_dir)
					.. " && zip -q " .. shell_escape(zip_name) .. " -- " .. shell_escape(file_name)
			)
		end
	else
		local paths_table = {}
		for _, u in ipairs(urls) do table.insert(paths_table, shell_escape(u)) end
		ok_zip, zip_output, zip_code = run_command_capture(
			"zip -qr " .. shell_escape(zip_name) .. " -- " .. table.concat(paths_table, " ")
		)
	end

	if not ok_zip then
		notify_zip_failure(zip_output, zip_code)
		return nil
	end

	return zip_name
end

local function get_share_urls(urls, app_name)
	if app_name == AIRDROP_LABEL then
		return urls
	end

	if any_directory(urls) then
		cleanup_old_zip_artifacts()
		local zip_name = create_zip_file(urls)
		if not zip_name then return nil end
		return { zip_name }
	end

	return urls
end

-- 5. Zip helpers
local function perform_zip_action(urls)
	local zip_name = create_zip_file(urls)
	if not zip_name then
		return false
	end

	if not copy_file_objects({ zip_name }, "The archive was created, but couldn't be copied to the clipboard.") then
		return false
	end

	return true
end

return {
	entry = function(self, job)
		local action = job.args[1]

		-- Directory-level actions
		if action == "open_vscode" then
			local cwd = get_cwd()
			run_command_or_notify(
				"open -a " .. shell_escape("Visual Studio Code") .. " " .. shell_escape(cwd),
				"Couldn't open Visual Studio Code."
			)
			return
		elseif action == "open_cursor" then
			local cwd = get_cwd()
			run_command_or_notify(
				"open -a " .. shell_escape("Cursor") .. " " .. shell_escape(cwd),
				"Couldn't open Cursor."
			)
			return
		elseif action == "open_finder" then
			local cwd = get_cwd()
			run_command_or_notify("open " .. shell_escape(cwd), "Couldn't open the current folder in Finder.")
			return

		-- File actions
		else
			local urls = get_selected_urls_or_notify()
			if not urls then return end

			if action == "smart_zip" then
				cleanup_old_zip_artifacts()
				perform_zip_action(urls)
			elseif action == "share_menu" then
				local cands = {}
				for k, v in pairs(config.share_apps) do table.insert(cands, { on = k, desc = v }) end
				table.insert(cands, { on = "a", desc = AIRDROP_LABEL })
				table.sort(cands, function(a, b) return a.on < b.on end)
				local idx = ya.which { cands = cands }
				if not idx then return end
				local sel = cands[idx]
				
				if sel.on == "a" then
					share_via_airdrop(urls)
				else
					local share_urls = get_share_urls(urls, sel.desc)
					if not share_urls then return end
					if not copy_file_objects(share_urls, "Couldn't prepare the selected items for sharing.") then return end
					run_command_or_notify(
						"open -a " .. shell_escape(sel.desc),
						"Couldn't open " .. sel.desc .. "."
					)
				end
			elseif action == "copy_file" then
				copy_file_objects(urls, "Couldn't copy the selected items.")
			end
		end
	end
}
