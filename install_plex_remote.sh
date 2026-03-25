#!/bin/bash
# Plex Media Server Remote Installation Script
# Uses command_guard.sh and handle_state.sh libraries

set -euo pipefail

# Source the libraries
source "$(dirname "$0")/config/command_guard.sh"
source "$(dirname "$0")/config/handle_state.sh"

# Configuration
REMOTE_HOST="${1:-}"
if [ -z "$REMOTE_HOST" ]; then
  echo "Error: REMOTE_HOST not specified. Usage: $0 user@remote-host [config-dir] [compose-file]"
  exit 1
fi

PLEX_CONFIG_DIR="${2:-/opt/plex}"
DOCKER_COMPOSE_FILE="${3:-docker-compose.yml}"

# Guard essential commands
guard ssh
guard scp
guard docker
guard docker-compose

# Function to run a command on the remote host.
# The command string ($1) is expanded by the LOCAL shell before being sent —
# it is transmitted verbatim (exactly as shown in the notification below) and
# evaluated by bash on the remote side.
#
# To defer variable or command substitution to the remote side, escape the $ sign:
#
# Examples:
#   remote_exec "echo 'Remote host is reachable'"                 # literal string
#   remote_exec "mkdir -p $PLEX_CONFIG_DIR"                       # expanded locally → verbatim on remote
#   remote_exec "echo \$HOME"                                     # \$ → $HOME expanded on remote
#   remote_exec "echo \$(uname -m)"                               # \$(...) → subcommand runs on remote
#   remote_exec "curl -L \"https://example.com/\$(uname -s)-\$(uname -m)\""
#                                                                 # URL built with remote arch/OS values
remote_exec() {
    local cmd="$1"
    echo "Executing on $REMOTE_HOST: $cmd"
    ssh "$REMOTE_HOST" 'bash -s' <<< "$cmd"
}

# Function to copy file to remote host
remote_copy() {
    local src="$1"
    local dst="$2"
    echo "Copying $src to $REMOTE_HOST:$dst"
    scp "$src" "$REMOTE_HOST:$dst"
}

# Initialize state
hs_setup_output_to_stdout

# Check remote connectivity
echo "Checking remote host connectivity..."
remote_exec "echo 'Remote host is reachable'"

# Install Docker if not present
echo "Ensuring Docker is installed on remote host..."
remote_exec "
if ! command -v docker >/dev/null 2>&1; then
    echo 'Installing Docker...'
    curl -fsSL https://get.docker.com -o get-docker.sh
    sh get-docker.sh
    systemctl enable docker
    systemctl start docker
else
    echo 'Docker is already installed'
fi
"

# Install Docker Compose if not present
echo "Ensuring Docker Compose is installed..."
remote_exec "
if ! command -v docker-compose >/dev/null 2>&1; then
    echo 'Installing Docker Compose...'
    curl -L \"https://github.com/docker/compose/releases/download/v2.24.0/docker-compose-\$(uname -s)-\$(uname -m)\" -o /usr/local/bin/docker-compose
    chmod +x /usr/local/bin/docker-compose
else
    echo 'Docker Compose is already installed'
fi
"

# Create Plex config directory
echo "Creating Plex configuration directory..."
remote_exec "mkdir -p $PLEX_CONFIG_DIR"

# Copy Docker Compose file
echo "Copying Docker Compose configuration..."
# Assume the docker-compose.yml is in the current directory
if [ -f "$DOCKER_COMPOSE_FILE" ]; then
    remote_copy "$DOCKER_COMPOSE_FILE" "$PLEX_CONFIG_DIR/"
else
    echo "Warning: $DOCKER_COMPOSE_FILE not found locally, skipping copy"
fi

# Start Plex
echo "Starting Plex Media Server..."
remote_exec "cd $PLEX_CONFIG_DIR && docker-compose up -d"

# Persist installation state
hs_persist_state -S install_state PLEX_INSTALLED=1 REMOTE_HOST="$REMOTE_HOST" CONFIG_DIR="$PLEX_CONFIG_DIR"

echo "Plex Media Server installation completed on $REMOTE_HOST"
echo "Access Plex at http://$REMOTE_HOST:32400/web"