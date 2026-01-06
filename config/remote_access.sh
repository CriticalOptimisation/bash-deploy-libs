#!/bin/bash
# Helper library for remote access operations used by installer scripts.
#
# This file provides small, well-specified functions that ensure that the
# remote host is reachable, that SSH access is available, that docker compose is installed,
# and that a service account exists.
#  - DNS / ping checks
#  - SSH reachability (with optional temporary ssh-agent helper)
#  - Docker Compose installation check
#  - Remote service account checks and (attempted) creation
#
# Design constraints:
#  - Do NOT rely on global error handling (no set -e/ERR traps). Each function
#    returns explicit exit codes and prints informative messages; callers must
#    check return values and decide how to react.
#  - Functions accept parameters and are safe to call from other scripts.
#  - Keep output machine- and human-friendly.

# Usage example (simplified):
#   source remote_access.sh
#   check_dns_and_ping "remote.example.com" || exit 3
#   ensure_ssh_access "remote.example.com" || exit 3
#   ensure_remote_user "remote.example.com" "plex" true || exit 5
#   prepare_upload_from_git "main" UPLOAD_DIR || exit 6
#   sync_files_to_remote "$UPLOAD_DIR" "/home/plex" "remote.example.com" "plex" files subdirs || exit 7

# NOTE: This module deliberately prints clear messages and returns non-zero
# values on errors; it does not abort the caller by itself.

# --- Initialization -------------------------------------------------------
# Exit code for missing dependencies
readonly RA_ERR_MISSING_DEPENDENCY=100
readonly RA_ERR_DNS_FAILURE=103
readonly RA_ERR_HOST_UNREACHABLE=104
readonly RA_ERR_SSH_NOT_INSTALLED=105
readonly RA_ERR_SSH_AGENT_NOT_INSTALLED=106
readonly RA_ERR_SSH_AGENT_FAILED_TO_START=107
readonly RA_ERR_NO_VALID_SSH_KEY=108
readonly RA_ERR_MISSING_PARAMETER=109

# --- Logging helpers -------------------------------------------------------
log_err() {
	echo "[ERROR] $*" >&2
}

log_warn() {
	echo "[WARN] $*" >&2
}

log_info() {
	# do not call before successful setup of hs_echo by sourcing handle_state.sh
	hs_echo "$*"
}

# Try to source `handle_state.sh` helpers if available
_ra_script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [ ! -f "${_ra_script_dir}/handle_state.sh" ]; then
	log_err "FATAL: handle_state.sh not found at ${_ra_script_dir}/handle_state.sh"
	log_err "Installation incomplete. Please ensure all library files are present."
	exit "$RA_ERR_MISSING_DEPENDENCY"
fi

# shellcheck source=./handle_state.sh
# shellcheck disable=SC1091
source "${_ra_script_dir}/handle_state.sh"

# --- Basic checks ---------------------------------------------------------
# Function:
#   ensure_dns_works_and_host_is_reachable <remote_host>
# Description:
#   Ensures that DNS resolution works for <remote_host> and that it is reachable
#   via ping. Prints informative messages on stderr and returns non-zero on failure.
# Returns:
#   0 if DNS resolution and a single ping succeeds.
#	RA_ERR_DNS_FAILURE if DNS resolution fails.
#	RA_ERR_HOST_UNREACHABLE if ping fails.
# Usage:
#  ensure_dns_works_and_host_is_reachable "remote.example.com" || exit 3
ra_ensure_dns_works_and_host_is_reachable() {
	# Assert that a remote host is provided
	if [ -z "$1" ]; then
		log_err "Usage: ra_ensure_dns_works_and_host_is_reachable <remote_host>"
		return "$RA_ERR_MISSING_PARAMETER"
	fi
	local remote_host="$1"
	# Prefer `getent hosts` (uses system resolver) for portability; fall back to nslookup/host if needed.
	if command -v getent >/dev/null 2>&1; then
		if ! getent hosts "$remote_host" >/dev/null 2>&1; then
			log_err "DNS resolution for $remote_host failed (getent)."
			return $RA_ERR_DNS_FAILURE
		fi
	elif command -v nslookup >/dev/null 2>&1; then
		if ! nslookup "$remote_host" >/dev/null 2>&1; then
			log_err "DNS resolution for $remote_host failed (nslookup)."
			return $RA_ERR_DNS_FAILURE
		fi
	elif command -v host >/dev/null 2>&1; then
		if ! host "$remote_host" >/dev/null 2>&1; then
			log_err "DNS resolution for $remote_host failed (host)."
			return $RA_ERR_DNS_FAILURE
		fi
	else
		log_warn "No common DNS lookup utility found (getent/nslookup/host); skipping DNS resolution test for $remote_host"
	fi

	if ! ping -c 1 "$remote_host" >/dev/null 2>&1; then
		log_err "Cannot reach $remote_host with ping!"
		return $RA_ERR_HOST_UNREACHABLE
	fi
	return 0
}

# --- SSH helpers ----------------------------------------------------------

# Function:
#   ensure_ssh_access <remote_host> [port [timeout_seconds]]
# Description:
#   Tries to run a non-interactive ssh command. If it fails and ssh-agent is
#   available, it tries to start a temporary agent and add keys with a short
#   timeout. Returns 0 on success, non-zero otherwise.
#   If it returns zero, the function prints on stdout a state snippet generated
#   by `hs_persist_state`. The caller should pass this snippet to the cleanup
#   function `stop_temporary_ssh_agent` to stop the temporary agent when done.
#   If it returns non-zero, it prints informative messages on stderr and
#   returns a meaningful error code.
# Parameters:
#   <remote_host>         The remote host to connect to (user@host or host
#                         depending on your SSH config).
#   [port]                Optional SSH port (default: 22).
#   [timeout_seconds]     Optional connection timeout in seconds (default: 1).
# Returns:
#   0 if SSH access is available.
#   RA_ERR_SSH_NOT_INSTALLED if ssh client is not installed.
#   RA_ERR_HOST_UNREACHABLE if SSH connection fails.
#   RA_ERR_SSH_AGENT_NOT_INSTALLED if ssh-agent is needed but not installed.
#   RA_ERR_SSH_AGENT_FAILED_TO_START if temporary ssh-agent could not be started.
#   RA_ERR_NO_VALID_SSH_KEY if no valid SSH key could be added to the
# State persistence:
#   If a running agent is detected without usable keys, the function calls
#   ssh-add to add keys for 60 seconds. 
#   If a temporary ssh-agent is started, the function emits a state snippet
#   that the caller should pass to the cleanup function to stop the agent.
# Usage:
#   state=$(ra_ensure_ssh_access "remote.example.com" 22 1) || exit 4
#   ...
ra_ensure_ssh_access() {
	# Read parameters
	local remote_host="$1"
	local port="${2:-22}"
	local timeout_seconds="${3:-1}"
	local SSH=/usr/bin/ssh
	readonly SSH

	# Validate parameters
	if [ -z "$remote_host" ]; then
		log_err "Remote host is required for ensure_ssh_access."
		return $RA_ERR_HOST_UNREACHABLE
	fi
	if [ -z "$port" ] || ! [[ "$port" =~ ^[0-9]+$ ]]; then
		log_err "Invalid port specified for ensure_ssh_access: $port"
		return $RA_ERR_HOST_UNREACHABLE
	fi
	if [ -z "$timeout_seconds" ] || ! [[ "$timeout_seconds" =~ ^[0-9]+$ ]]; then
		log_err "Invalid timeout specified for ensure_ssh_access: $timeout_seconds"
		return $RA_ERR_HOST_UNREACHABLE
	fi
	# Test that ssh is installed
	if ! command -v "$SSH" >/dev/null 2>&1; then
		log_err "ssh client $SSH is not installed on this machine."
		return $RA_ERR_SSH_NOT_INSTALLED
	fi

	# Prepare ssh command
	local global_alias_defined=false
	eval "
ra_ssh() {
   \"$SSH\" -A -q -o BatchMode=yes -p \"$port\" -o ConnectTimeout=\"$timeout_seconds\" \"\$@\"
}"
	global_alias_defined=true

	ensure_dns_works_and_host_is_reachable "$remote_host" || return $?

	# Test connection
	if ra_ssh "$remote_host" exit >/dev/null 2>&1; then
		log_info "# SSH access to $remote_host OK"
		hs_persist_state global_alias_defined
		return 0
	fi

	log_warn "No immediate SSH access to $remote_host."

	# Try to use an existing agent first. 
	# Attempt to add keys from common locations.
	if ! [ -n "${SSH_AUTH_SOCK:-}" ]; then
	    # There is no existing, reachable agent
		log_info "Starting temporary ssh-agent to attempt access"
		local ssh_agent_started=false
		if ! command -v ssh-agent >/dev/null 2>&1; then
			log_err "ssh-agent is not installed on this machine."
			return $RA_ERR_SSH_AGENT_NOT_INSTALLED
		fi

		# Start a temporary agent and add keys for a short duration
		local agent_output
		agent_output=$(ssh-agent -s 2>/dev/null) || {
			log_err "Failed to start ssh-agent"
			return $RA_ERR_SSH_AGENT_FAILED_TO_START
		}
		# Do not interfere with any future agents in this shell
		local SSH_AUTH_SOCK
		local SSH_AGENT_PID
		eval "$agent_output"
		ssh_agent_started=true
	fi

	if [ -n "${SSH_AUTH_SOCK:-}" ]; then
	    # The agent is operational but obviously has no valid keys for remote_host
		# Try to add keys from common locations
		log_info "Existing ssh-agent has no valid keys; attempting to add keys from ~/.ssh"
		local _added_any=false
		for _k in ~/.ssh/id_ed25519 ~/.ssh/id_rsa ~/.ssh/id_ecdsa ~/.ssh/*.pem; do
			[ -f "$_k" ] || continue
			# Try to add non-interactively; ignore failures (may be passphrase-protected)
			ssh-add -q -t 60 "$_k" >/dev/null 2>&1 && _added_any=true || true
		done
		if [ "$_added_any" = false ]; then
			log_err "No SSH keys could be added to the agent."
			# No need to try further
			ra_cleanup_ssh_access "$(hs_persist_state SSH_AUTH_SOCK SSH_AGENT_PID global_alias_defined ssh_agent_started)"
			return "$RA_ERR_NO_VALID_SSH_KEY"
		fi
	fi

	if ra_ssh "$remote_host" exit >/dev/null 2>&1; then
		hs_persist_state SSH_AUTH_SOCK SSH_AGENT_PID global_alias_defined ssh_agent_started
		return 0
	fi

	log_err "No SSH key suitable for connection to $remote_host."
	log_info "Please run 'eval \\$(ssh-agent)' and 'ssh-add <key_file>' in your shell, then retry."
	return "$RA_ERR_NO_VALID_SSH_KEY"
}

ra_cleanup_ssh_access()
{
	local SSH_AUTH_SOCK
	local SSH_AGENT_PID
	local global_alias_defined
	local ssh_agent_started
	eval "$(hs_read_persisted_state "$1")"
	if [ "$global_alias_defined" = true ]; then
		unset -f ra_ssh
	fi
	if [ "$ssh_agent_started" = true ] && [ -n "${SSH_AGENT_PID:-}" ]; then
		ssh-agent -k >/dev/null 2>&1
		log_info "Stopped temporary ssh-agent (PID $SSH_AGENT_PID)"
	fi
}

# --- Remote account management --------------------------------------------
# Function:
#   ra_ensure_remote_user
# Description:
#   Ensures that <remote_user> exists on <remote_host>. If it doesn't, attempts
#   to create it (requires sudo on the remote host). Returns 0 on success.
# Parameters:
#   <remote_host>   The remote host to connect to (user@host or host
#                   depending on your SSH config).
#   <remote_user>   The remote user to check/create.
#   <assume_yes>    If true, assumes 'yes' to any prompts when encountering
#                   an existing user.
# Returns:
#   0 if the user exists or was created successfully.
#   Non-zero otherwise.
#   Can return any code returned by ra_ensure_ssh_access.
# State persistence:
#   Saves the name of the remote user in case it is needed for cleanup.
# Usage:
#   ra_ensure_remote_user "remote.example.com" "plex" true || exit
ra_ensure_remote_user() {
	local remote_host="$1"
	local remote_user="$2"
	local assume_yes="$3"
	local SSH_CALL=(ssh -A -q -o BatchMode=yes -o ConnectTimeout=1)

	if ! "${SSH_CALL[@]}" "$remote_host" getent group "$remote_user" >/dev/null 2>&1; then
		log_warn "The group '$remote_user' does not exist on $remote_host"
	fi

	if "${SSH_CALL[@]}" "$remote_host" id -u "$remote_user" >/dev/null 2>&1; then
		log_info "Remote user '$remote_user' exists on $remote_host"
		return 0
	fi

	log_info "Attempting to create service account '$remote_user' on $remote_host"
	local cmd
	cmd=(sudo useradd -rmU -c "service account" -s /usr/sbin/nologin -G docker "$remote_user")
	local rc=0
	# Use -t to force pseudo-tty so sudo can prompt if needed
	"${SSH_CALL[@]}" -t "$remote_host" "${cmd[*]}" || rc=$?

	if [ $rc -ne 0 ]; then
		if [ $rc -eq 9 ]; then
			log_warn "Account $remote_user already exists (rc=9)."
			if [ "$assume_yes" = true ]; then
				log_info "Assuming existing account is suitable (assume_yes=true)"
				return 0
			fi
			# Ask user locally whether to continue
			read -r -p "User $remote_user already exists on $remote_host. Continue? [y/N] " answer
			answer=${answer,,}
			if [[ -z "$answer" || "$answer" == "n" || "$answer" == "no" ]]; then
				log_err "Operation aborted by user."
				return 6
			fi
			return 0
		fi
		log_err "Failed to create remote user '$remote_user' (rc=$rc)."
		return 7
	fi

	log_info "Service account '$remote_user' created on $remote_host"
	return 0
}

# --- Cleanup helpers -------------------------------------------------------
# Function:
#   stop_temporary_ssh_agent
# Description:
#   Stops the temporary ssh-agent started by ensure_ssh_access.
# Usage:
#   stop_temporary_ssh_agent "$state"
stop_temporary_ssh_agent() {
	local SSH_AGENT_PID
	local SSH_AUTH_SOCK
	eval "$(hs_read_persisted_state "$1")"
	if [ -n "${SSH_AGENT_PID:-}" ]; then
		ssh-agent -k >/dev/null 2>&1
		log_info "Stopped temporary ssh-agent (PID $SSH_AGENT_PID)"
	else
		log_warn "No temporary ssh-agent to stop."	
	fi
}
# End of helpers


