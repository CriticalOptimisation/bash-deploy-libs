---
name: bash-path-prefix-scan
description: Expert guidance for scanning Bash scripts for PATH manipulation vulnerabilities, including detection of insecure PATH prefix operations and recommendations for secure practices. Triggers on requests like "check PATH security", "scan for PATH vulnerabilities", or "secure PATH handling".
---

# Bash PATH Prefix Scan Skill

## Purpose

This skill provides guidance on identifying and preventing PATH manipulation vulnerabilities in Bash scripts. It helps detect insecure PATH prefix operations that could lead to command injection or privilege escalation attacks.

## Overview

PATH prefix vulnerabilities occur when a script prepends user-controlled or untrusted directories to the PATH environment variable, potentially allowing an attacker to execute malicious commands before legitimate system commands.

## Common Vulnerability Patterns

### Dangerous Patterns

1. **Prepending user-controlled directories**:
   ```bash
   # VULNERABLE: User can control $HOME
   export PATH="$HOME/bin:$PATH"
   ```

2. **Prepending relative paths**:
   ```bash
   # VULNERABLE: Current directory could be attacker-controlled
   export PATH="./bin:$PATH"
   export PATH="bin:$PATH"
   ```

3. **Prepending world-writable directories**:
   ```bash
   # VULNERABLE: /tmp is world-writable
   export PATH="/tmp/tools:$PATH"
   ```

4. **Prepending without validation**:
   ```bash
   # VULNERABLE: No validation of directory
   new_path="$1"
   export PATH="$new_path:$PATH"
   ```

### Why These Are Dangerous

When an untrusted directory is prepended to PATH:
- An attacker can create malicious executables (e.g., fake `ls`, `cat`, `rm`)
- These malicious commands will be executed instead of system commands
- This can lead to data theft, privilege escalation, or system compromise

## Scanning for Vulnerabilities

### Manual Inspection

Look for these patterns in scripts:
```bash
grep -n "PATH=.*:" script.sh
grep -n "export PATH=" script.sh
grep -n "PATH=\".*:\$PATH\"" script.sh
```

### Key Questions to Ask

1. **Is the path hard-coded and trusted?**
   - ✓ Safe: `/usr/local/bin:$PATH`
   - ✗ Unsafe: `$1:$PATH` or `$HOME/bin:$PATH`

2. **Is the path absolute?**
   - ✓ Safe: `/opt/custom/bin:$PATH`
   - ✗ Unsafe: `./bin:$PATH` or `bin:$PATH`

3. **Is the directory writable only by trusted users?**
   - ✓ Safe: `/usr/local/bin` (requires root/admin)
   - ✗ Unsafe: `/tmp/bin` (world-writable)

4. **Is there validation before use?**
   - ✓ Safe: Checks ownership and permissions
   - ✗ Unsafe: Uses path without validation

## Secure Alternatives

### Option 1: Use Full Paths

```bash
# Instead of modifying PATH
/usr/local/bin/custom-tool args

# Or store the path
CUSTOM_TOOL="/usr/local/bin/custom-tool"
"$CUSTOM_TOOL" args
```

### Option 2: Append to PATH (Less Risk)

```bash
# Appending is generally safer than prepending
export PATH="$PATH:/usr/local/bin"

# But still validate if from untrusted source
```

### Option 3: Validate Before Adding

```bash
safe_add_to_path() {
    local dir="$1"
    
    # Validate directory exists and is absolute
    if [[ ! -d "$dir" ]]; then
        echo "Error: directory does not exist: $dir" >&2
        return 1
    fi
    
    if [[ "$dir" != /* ]]; then
        echo "Error: path must be absolute: $dir" >&2
        return 1
    fi
    
    # Check ownership (optional but recommended)
    local owner
    owner=$(stat -c '%U' "$dir" 2>/dev/null)
    if [[ "$owner" != "root" ]] && [[ "$owner" != "$USER" ]]; then
        echo "Warning: directory not owned by root or current user: $dir" >&2
    fi
    
    # Check it's not world-writable
    if [[ -w "$dir" ]] && [[ $(stat -c '%a' "$dir") =~ [0-9][0-9]7$ ]]; then
        echo "Error: directory is world-writable: $dir" >&2
        return 1
    fi
    
    # Safe to add
    export PATH="$dir:$PATH"
}
```

### Option 4: Use a Temporary PATH

```bash
# Create isolated PATH for specific operations
run_with_custom_path() {
    local custom_bin="/opt/trusted/bin"
    (
        # Subshell to isolate PATH change
        export PATH="$custom_bin:$PATH"
        "$@"
    )
}

run_with_custom_path some-command --args
```

## Automated Scanning Script

See [references/scan-script.sh](references/scan-script.sh) for a complete scanning script that can detect common PATH vulnerabilities.

### Quick Scan

```bash
# Scan a single file
./scan-script.sh path/to/script.sh

# Scan a directory recursively
find . -name "*.sh" -exec ./scan-script.sh {} \;
```

## Remediation Checklist

When fixing a PATH vulnerability:

- [ ] Identify all PATH modifications in the codebase
- [ ] For each modification, determine if it's necessary
- [ ] Replace with full paths if possible
- [ ] If PATH modification is required:
  - [ ] Ensure paths are absolute
  - [ ] Validate directory exists and has correct permissions
  - [ ] Check directory ownership
  - [ ] Document why the modification is safe
- [ ] Add comments explaining security considerations
- [ ] Test that legitimate functionality still works
- [ ] Consider adding runtime checks

## Security Best Practices

1. **Minimize PATH modifications**: Use full paths when possible
2. **Never trust user input**: Validate thoroughly before using in PATH
3. **Prefer appending over prepending**: Reduces attack surface
4. **Use absolute paths only**: Avoid relative paths
5. **Check permissions**: Ensure directories are not world-writable
6. **Isolate changes**: Use subshells to limit scope of PATH modifications
7. **Document security**: Explain why PATH modifications are safe
8. **Regular audits**: Periodically scan for new vulnerabilities

## Example Vulnerability and Fix

### Vulnerable Code

```bash
#!/bin/bash
# VULNERABLE: Allows user to control PATH

user_tools_dir="$1"
export PATH="$user_tools_dir:$PATH"

# These commands might execute attacker's code!
git pull
npm install
```

### Fixed Code

```bash
#!/bin/bash
# SECURE: Validates before use and uses full paths

safe_add_tools() {
    local tools_dir="$1"
    
    # Validate
    if [[ ! -d "$tools_dir" ]]; then
        echo "Error: tools directory not found" >&2
        return 1
    fi
    
    if [[ "$tools_dir" != /* ]]; then
        echo "Error: must use absolute path" >&2
        return 1
    fi
    
    # Check not world-writable
    local perms
    perms=$(stat -c '%a' "$tools_dir")
    if [[ "$perms" =~ 7$ ]]; then
        echo "Error: directory is world-writable" >&2
        return 1
    fi
    
    export PATH="$tools_dir:$PATH"
}

user_tools_dir="$1"
if [[ -n "$user_tools_dir" ]]; then
    safe_add_tools "$user_tools_dir" || exit 1
fi

# Use full paths for critical commands
/usr/bin/git pull
/usr/bin/npm install
```

## Related Resources

- [references/scan-script.sh](references/scan-script.sh) - Automated vulnerability scanner
- [references/examples.md](references/examples.md) - More examples of vulnerabilities and fixes

## References

- CWE-426: Untrusted Search Path
- OWASP: Command Injection
- Bash Security Best Practices

## Tips

- Always be suspicious of PATH modifications
- In production, consider making PATH immutable (readonly)
- Use tools like shellcheck for additional security checks
- Review any code that runs with elevated privileges extra carefully
