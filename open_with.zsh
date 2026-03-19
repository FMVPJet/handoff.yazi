#!/bin/zsh

set -u
setopt extendedglob
export PATH="/opt/homebrew/bin:/opt/homebrew/sbin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:${PATH:-}"

resolve_home_dir() {
	if [[ -n "${HANDOFF_HOME:-}" ]]; then
		print -r -- "${HANDOFF_HOME}"
		return
	fi

	if [[ -n "${SMART_ACTION_HOME:-}" ]]; then
		print -r -- "${SMART_ACTION_HOME}"
		return
	fi

	if [[ -n "${HOME:-}" ]]; then
		print -r -- "${HOME}"
		return
	fi

	local resolved_home=""
	resolved_home="$(cd ~ >/dev/null 2>&1 && pwd)" || true
	if [[ -n "$resolved_home" ]]; then
		print -r -- "$resolved_home"
		return
	fi

	print -r -- "$PWD"
}

HOME_DIR="$(resolve_home_dir)"
STATE_ROOT="${HANDOFF_STATE_ROOT:-${SMART_ACTION_STATE_ROOT:-${XDG_STATE_HOME:-${HOME_DIR}/.local/state}}}"
STATE_DIR="${STATE_ROOT}/yazi/handoff"
STATE_FILE="${STATE_DIR}/open_with_last.txt"
LEGACY_STATE_FILE="${STATE_ROOT}/yazi/smart-action/open_with_last.txt"

press_any_key() {
	print -r -- "Press any key to go back..."
	read -sk 1
}

require_command() {
	local command_name="$1"
	if command -v "$command_name" >/dev/null 2>&1; then
		return 0
	fi

	print -r -- "Required command not found: ${command_name}"
	press_any_key
	exit 127
}

require_command open
require_command find
require_command sort

FZF_BIN="$(command -v fzf 2>/dev/null || true)"
if [[ -z "$FZF_BIN" && -x /opt/homebrew/bin/fzf ]]; then
	FZF_BIN="/opt/homebrew/bin/fzf"
fi

if [[ -z "$FZF_BIN" ]]; then
	print -r -- "fzf is required for Open With."
	press_any_key
	exit 127
fi

typeset -a raw_paths target_paths
raw_paths=("$@")
for raw_path in "${raw_paths[@]}"; do
	[[ -n "$raw_path" ]] || continue
	target_paths+=("$raw_path")
done

if (( ${#target_paths[@]} == 0 )); then
	print -r -- "Nothing to open."
	press_any_key
	exit 2
fi

recent_app_path=""
if [[ -r "$STATE_FILE" ]]; then
	IFS= read -r recent_app_path < "$STATE_FILE" || true
elif [[ -r "$LEGACY_STATE_FILE" ]]; then
	IFS= read -r recent_app_path < "$LEGACY_STATE_FILE" || true
fi

discover_apps() {
	local query='kMDItemContentType == "com.apple.application-bundle"'
	mdfind "$query" 2>/dev/null

	local search_roots=(
		"/Applications"
		"/Applications/Setapp"
		"/System/Applications"
		"/System/Applications/Utilities"
		"${HOME:-}/Applications"
	)

	for search_root in "${search_roots[@]}"; do
		[[ -d "$search_root" ]] || continue
		find "$search_root" -maxdepth 3 -type d -name "*.app" 2>/dev/null
	done
}

build_app_list() {
	typeset -A seen_paths seen_names
	typeset -a app_lines
	local app_path app_name line recent_line

	while IFS= read -r app_path; do
		[[ -n "$app_path" && -d "$app_path" ]] || continue
		if [[ -n "${seen_paths[$app_path]-}" ]]; then
			continue
		fi
		seen_paths[$app_path]=1
		app_name="${app_path:t:r}"

		if [[ -z "${seen_names[$app_name]-}" ]]; then
			seen_names[$app_name]="$app_path"
			line="${app_name}"$'\t'"${app_path}"
			if [[ -n "$recent_app_path" && "$app_path" == "$recent_app_path" ]]; then
				recent_line="$line"
			else
				app_lines+=("$line")
			fi
		fi
	done < <(discover_apps | LC_ALL=C sort -u)

	if [[ -n "${recent_line:-}" ]]; then
		print -r -- "$recent_line"
	fi
	print -rl -- "${app_lines[@]}"
}

header='Type to filter apps, arrows to move, Enter to open'
if [[ -n "$recent_app_path" && -d "$recent_app_path" ]]; then
	header+=$'\nRecent: '"${recent_app_path:t:r}"
fi

selected_line="$(
	build_app_list | "$FZF_BIN" \
		--layout=reverse \
		--height=80% \
		--prompt='open-with> ' \
		--delimiter=$'\t' \
		--with-nth=1 \
		--header="$header"
)"
exit_code=$?
if (( exit_code != 0 )); then
	exit "$exit_code"
fi

selected_app_path="${selected_line#*$'\t'}"
if [[ -z "$selected_app_path" || ! -d "$selected_app_path" ]]; then
	print -r -- "The selected app could not be resolved."
	press_any_key
	exit 1
fi

if open -a "$selected_app_path" -- "${target_paths[@]}"; then
	mkdir -p -- "$STATE_DIR" >/dev/null 2>&1 || true
	print -r -- "$selected_app_path" >| "$STATE_FILE" 2>/dev/null || true
	exit 0
fi

print -r -- "Couldn't open the selected items with ${selected_app_path:t:r}."
press_any_key
exit 1
