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

resolve_temp_root() {
	local temp_root="${TMPDIR:-/tmp}"
	temp_root="${temp_root%/}"
	if [[ -z "$temp_root" ]]; then
		temp_root="/tmp"
	fi
	print -r -- "$temp_root"
}

HOME_DIR="$(resolve_home_dir)"
TEMP_ROOT="$(resolve_temp_root)"

HANDOFF_REMOTE_SYNC_DEBUG="${HANDOFF_REMOTE_SYNC_DEBUG:-${SMART_ACTION_REMOTE_SYNC_DEBUG:-0}}"
DEBUG_ENABLED=0
if [[ "$HANDOFF_REMOTE_SYNC_DEBUG" == "1" || "$HANDOFF_REMOTE_SYNC_DEBUG" == "true" ]]; then
	DEBUG_ENABLED=1
fi

DEBUG_LOG="${HANDOFF_REMOTE_SYNC_DEBUG_LOG:-${SMART_ACTION_REMOTE_SYNC_DEBUG_LOG:-${TEMP_ROOT}/handoff-remote-sync-debug.log}}"
STATE_ROOT="${HANDOFF_STATE_ROOT:-${SMART_ACTION_STATE_ROOT:-${XDG_STATE_HOME:-${HOME_DIR}/.local/state}}}"
STATE_DIR="${STATE_ROOT}/yazi/handoff"
STATE_FILE="${STATE_DIR}/remote_sync_last.tsv"
LEGACY_STATE_FILE="${STATE_ROOT}/yazi/smart-action/remote_sync_last.tsv"

debug_log() {
	(( DEBUG_ENABLED )) || return 0
	print -r -- "$*" >> "$DEBUG_LOG"
}

if (( DEBUG_ENABLED )); then
	: > "$DEBUG_LOG"
	debug_log "=== $(date '+%Y-%m-%d %H:%M:%S') ==="
	debug_log "argv_count=$#"
	debug_log "pwd=$PWD"
	debug_log "home=${HOME:-<empty>}"
	debug_log "home_dir=$HOME_DIR"
	debug_log "temp_root=$TEMP_ROOT"
	debug_log "path=$PATH"
fi

require_command() {
	local command_name="$1"
	if command -v "$command_name" >/dev/null 2>&1; then
		debug_log "command:$command_name=$(command -v "$command_name")"
		return 0
	fi

	print -r -- "Required command not found: ${command_name}"
	print -r -- "Current PATH: ${PATH}"
	print -r -- "Press any key to go back..."
	read -sk 1
	exit 127
}

FZF_BIN="$(command -v fzf 2>/dev/null || true)"
if [[ -z "$FZF_BIN" && -x /opt/homebrew/bin/fzf ]]; then
	FZF_BIN="/opt/homebrew/bin/fzf"
fi

if [[ -z "$FZF_BIN" ]]; then
	print -r -- "fzf is required for Remote Sync."
	print -r -- "Press any key to go back..."
	read -sk 1
	exit 127
fi

require_command ssh
require_command rsync
require_command find
require_command sort
require_command mkdir

cwd="$PWD"
default_path="~"
project_node="${cwd:t}"
if [[ -n "$project_node" && "$project_node" != "/" && "$project_node" != "." ]]; then
	default_path="~/$project_node"
fi

SSH_CONFIG_PATH="${HANDOFF_SSH_CONFIG_PATH:-${SMART_ACTION_SSH_CONFIG_PATH:-${HOME_DIR}/.ssh/config}}"
debug_log "ssh_config_path=$SSH_CONFIG_PATH"
if [[ -e "$SSH_CONFIG_PATH" ]]; then
	debug_log "ssh_config_stat=$(ls -ld "$SSH_CONFIG_PATH" 2>/dev/null)"
	debug_log "ssh_config_head=$(sed -n '1,5p' "$SSH_CONFIG_PATH" 2>/dev/null | tr '\n' '|' )"
else
	debug_log "ssh_config_missing=1"
fi

recent_host=""
recent_path=""
if [[ -r "$STATE_FILE" ]]; then
	IFS=$'\t' read -r recent_host recent_path < "$STATE_FILE" || true
elif [[ -r "$LEGACY_STATE_FILE" ]]; then
	IFS=$'\t' read -r recent_host recent_path < "$LEGACY_STATE_FILE" || true
fi
debug_log "state_file=$STATE_FILE"
debug_log "recent_host=${recent_host:-<empty>}"
debug_log "recent_path=${recent_path:-<empty>}"

typeset -a raw_paths source_paths
raw_paths=("$@")
debug_log "raw_paths=${(j: | :)raw_paths}"
for source_path in "${raw_paths[@]}"; do
	[[ -n "$source_path" ]] || continue
	if [[ ! " ${source_paths[*]} " == *" $source_path "* ]]; then
		source_paths+=("$source_path")
	fi
done
debug_log "source_paths=${(j: | :)source_paths}"

if (( ${#source_paths[@]} == 0 )); then
	print -r -- "Nothing to upload."
	print -r -- "Press any key to go back..."
	read -sk 1
	exit 2
fi

parse_hosts() {
	[[ -r "$SSH_CONFIG_PATH" ]] || return 1
	typeset -A seen_hosts
	local line trimmed rest token

	while IFS= read -r line || [[ -n "$line" ]]; do
		trimmed="${line##[[:space:]]#}"
		if [[ ! "$trimmed" == [Hh][Oo][Ss][Tt][[:space:]]* ]]; then
			continue
		fi

		rest="${trimmed#[Hh][Oo][Ss][Tt][[:space:]]#}"
		for token in ${(z)rest}; do
			[[ "$token" == "*" || "$token" == *[\*\?\!]* ]] && continue
			if [[ -z "${seen_hosts[$token]-}" ]]; then
				seen_hosts[$token]=1
				print -r -- "$token"
			fi
			break
		done
	done < "$SSH_CONFIG_PATH"
}

typeset -a hosts
host_output="$(parse_hosts)"
debug_log "parse_hosts_exit=$?"
debug_log "parse_hosts_raw=${host_output//$'\n'/|}"
for host in "${(@f)host_output}"; do
	[[ -n "$host" ]] || continue
	hosts+=("$host")
done
debug_log "host_count=${#hosts[@]}"
debug_log "hosts=${(j: | :)hosts}"
if (( ${#hosts[@]} == 0 )); then
	print -r -- "No valid SSH hosts were found in ${SSH_CONFIG_PATH}."
	print -r -- "Press any key to go back..."
	read -sk 1
	exit 1
fi

if [[ -n "$recent_host" ]]; then
	typeset -a remaining_hosts
	recent_found=0
	for host in "${hosts[@]}"; do
		if [[ "$host" == "$recent_host" ]]; then
			recent_found=1
		else
			remaining_hosts+=("$host")
		fi
	done
	if (( recent_found )); then
		hosts=("$recent_host" "${remaining_hosts[@]}")
	else
		recent_host=""
		recent_path=""
	fi
fi

host_header=$'Type to filter hosts, arrows to move, Enter to select'
if [[ -n "$recent_host" ]]; then
	host_header+=$'\nRecent: '"${recent_host}"
fi

selected_host="$(printf '%s\n' "${hosts[@]}" | "$FZF_BIN" \
	--layout=reverse \
	--height=80% \
	--prompt='host> ' \
	--header="$host_header")"
exit_code=$?
if (( exit_code != 0 )); then
	exit "$exit_code"
fi

ssh_opts=(
	-o BatchMode=yes
	-o ConnectTimeout=5
	-o ConnectionAttempts=1
	-o NumberOfPasswordPrompts=0
)

fetch_listing() {
	local requested_path="$1"
	listing="$(ssh "${ssh_opts[@]}" "$selected_host" sh -s -- "$requested_path" <<'EOSH' 2>&1
input_path=$1
case "$input_path" in
	"~") input_path=$HOME ;;
	"~/"*) input_path=$HOME/${input_path#~/} ;;
esac
if [ ! -d "$input_path" ]; then
	printf 'NOT_A_DIRECTORY: %s\n' "$input_path" >&2
	exit 3
fi
cd -- "$input_path" || exit 3
pwd
find . -mindepth 1 -maxdepth 1 -type d -print 2>/dev/null | LC_ALL=C sort | while IFS= read -r entry; do
	name=${entry#./}
	[ -n "$name" ] || continue
	printf '%s\n' "$name"
done
EOSH
	)"
	return $?
}

remote_join_path() {
	local base="$1"
	local name="$2"
	if [[ "$base" == "/" ]]; then
		print -r -- "/$name"
	else
		print -r -- "${base%/}/$name"
	fi
}

remote_shell_escape() {
	local value="$1"
	print -r -- "'"${value//\'/\'\"\'\"\'}"'"
}

build_copied_remote_path() {
	if (( ${#source_paths[@]} == 1 )); then
		local source_name="${source_paths[1]:t}"
		remote_join_path "$target_path" "$source_name"
		return
	fi

	print -r -- "$target_path"
}

copy_text_to_clipboard() {
	local text="$1"
	printf '%s' "$text" | pbcopy
}

show_error_and_exit() {
	print -r -- "$1"
	print -r -- "--------------------------------"
	print -r -- "$2"
	print -r -- "Press any key to go back..."
	read -sk 1
	exit "${3:-1}"
}

typeset -a start_paths
if [[ -n "$recent_host" && -n "$recent_path" && "$selected_host" == "$recent_host" ]]; then
	start_paths+=("$recent_path")
fi
if (( ${#start_paths[@]} == 0 )) || [[ "${start_paths[-1]}" != "$default_path" ]]; then
	start_paths+=("$default_path")
fi
if [[ "${start_paths[-1]}" != "~" ]]; then
	start_paths+=("~")
fi
debug_log "start_paths=${(j: | :)start_paths}"

exit_code=1
for candidate_path in "${start_paths[@]}"; do
	current_path="$candidate_path"
	fetch_listing "$current_path"
	exit_code=$?
	debug_log "fetch_start_path=${candidate_path} exit=${exit_code}"
	if (( exit_code == 0 )); then
		break
	fi
done

if (( exit_code != 0 )); then
	show_error_and_exit "$listing" "Unable to read the remote directory" "$exit_code"
fi

while true; do
	resolved_path="${listing%%$'\n'*}"
	lines=("${(@f)listing}")
	lines=("${(@)lines[2,-1]}")

	candidates=()
	candidates+=("[Use this directory]")
	if [[ "$resolved_path" != "/" ]]; then
		candidates+=("../")
	fi
	for dir_name in "${lines[@]}"; do
		[[ -n "$dir_name" ]] || continue
		candidates+=("${dir_name}/")
	done

	selected="$(printf '%s\n' "${candidates[@]}" | "$FZF_BIN" \
		--layout=reverse \
		--height=80% \
		--prompt='dir> ' \
		--header=$'Type to filter directories, arrows to move, Enter to select\nHost: '"${selected_host}"$'\nPath: '"${resolved_path}")"
	exit_code=$?
	if (( exit_code != 0 )); then
		exit "$exit_code"
	fi

	if [[ "$selected" == "[Use this directory]" ]]; then
		target_path="$resolved_path"
		break
	elif [[ "$selected" == "../" ]]; then
		if [[ "$resolved_path" == "/" ]]; then
			current_path="/"
		else
			current_path="${resolved_path:h}"
			[[ -n "$current_path" ]] || current_path="/"
		fi
	else
		selected="${selected%/}"
		if [[ "$resolved_path" == "/" ]]; then
			current_path="/$selected"
		else
			current_path="$resolved_path/$selected"
		fi
	fi

	fetch_listing "$current_path"
	exit_code=$?
	if (( exit_code != 0 )); then
		show_error_and_exit "$listing" "Unable to read the remote directory" "$exit_code"
	fi
done

print -r -- "Host: ${selected_host}"
print -r -- "Destination: ${target_path}"
print -r -- "--------------------------------"

rsync_target="${selected_host}:$(remote_shell_escape "$target_path")"

rsync -azP8 \
	-e "ssh -o BatchMode=yes -o ConnectTimeout=5 -o ConnectionAttempts=1 -o NumberOfPasswordPrompts=0" \
	--stats -- "${source_paths[@]}" "$rsync_target"
exit_code=$?

if (( exit_code == 0 )); then
	if mkdir -p -- "$STATE_DIR" 2>>"$DEBUG_LOG"; then
		if ! print -r -- "${selected_host}"$'\t'"${target_path}" >| "$STATE_FILE" 2>>"$DEBUG_LOG"; then
			debug_log "state_write_failed=1"
		else
			debug_log "state_write_ok=1"
		fi
	else
		debug_log "state_dir_create_failed=1"
	fi

	copied_remote_path="$(build_copied_remote_path)"
	copied_path_label="target directory"
	if (( ${#source_paths[@]} == 1 )); then
		copied_path_label="remote path"
	fi

	copied_path_ok=0
	if copy_text_to_clipboard "$copied_remote_path"; then
		copied_path_ok=1
	else
		debug_log "clipboard_copy_failed=1"
	fi

	print -r -- "--------------------------------"
	if (( copied_path_ok )); then
		print -r -- "Copied ${copied_path_label}: ${copied_remote_path}"
	else
		print -r -- "Sync finished, but the ${copied_path_label} couldn't be copied."
	fi
	print -r -- "Sync complete. Press any key to go back..."
	read -sk 1
	exit 0
fi

print -r -- "--------------------------------"
print -r -- "Sync failed (exit code: ${exit_code})"
print -r -- "Press any key to go back..."
read -sk 1
exit "$exit_code"
