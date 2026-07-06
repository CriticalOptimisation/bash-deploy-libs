#!/usr/bin/env bash
# PATH Vulnerability Scanner
# Scans Bash scripts for insecure PATH manipulation patterns

set -euo pipefail

# Colors for output
readonly RED='\033[0;31m'
readonly YELLOW='\033[1;33m'
readonly GREEN='\033[0;32m'
readonly NC='\033[0m' # No Color

# Counters
TOTAL_FILES=0
VULNERABLE_FILES=0
TOTAL_ISSUES=0

# Vulnerability patterns
declare -A PATTERNS=(
    ["relative_path"]='PATH=["'"'"']?\.{0,2}/[^:]*:[^"'"'"']*'
    ["variable_prepend"]='PATH=["'"'"']?\$[{]?[A-Za-z_][A-Za-z0-9_]*[}]?:[^"'"'"']*\$PATH'
    ["tmp_prepend"]='PATH=["'"'"']?/tmp[^:]*:[^"'"'"']*\$PATH'
    ["home_prepend"]='PATH=["'"'"']?\$HOME[^:]*:[^"'"'"']*\$PATH'
)

# Check if file is a shell script
is_shell_script() {
    local file="$1"
    
    # Check extension
    if [[ "$file" =~ \.sh$ ]]; then
        return 0
    fi
    
    # Check shebang
    if [[ -f "$file" ]]; then
        local first_line
        first_line=$(head -n 1 "$file" 2>/dev/null || echo "")
        if [[ "$first_line" =~ ^#!.*bash ]]; then
            return 0
        fi
    fi
    
    return 1
}

# Scan a file for vulnerabilities
scan_file() {
    local file="$1"
    local found_issues=0
    
    if [[ ! -f "$file" ]]; then
        echo "Error: File not found: $file" >&2
        return 1
    fi
    
    if ! is_shell_script "$file"; then
        return 0
    fi
    
    TOTAL_FILES=$((TOTAL_FILES + 1))
    
    # Scan for each pattern
    for pattern_name in "${!PATTERNS[@]}"; do
        local pattern="${PATTERNS[$pattern_name]}"
        local matches
        
        matches=$(grep -n -E "$pattern" "$file" 2>/dev/null || true)
        
        if [[ -n "$matches" ]]; then
            if [[ $found_issues -eq 0 ]]; then
                echo -e "${RED}[VULNERABLE]${NC} $file"
                VULNERABLE_FILES=$((VULNERABLE_FILES + 1))
            fi
            
            echo -e "  ${YELLOW}Issue:${NC} $pattern_name"
            
            while IFS= read -r match; do
                local line_num="${match%%:*}"
                local line_content="${match#*:}"
                echo "    Line $line_num: $line_content"
                TOTAL_ISSUES=$((TOTAL_ISSUES + 1))
                found_issues=$((found_issues + 1))
            done <<< "$matches"
            
            echo ""
        fi
    done
    
    return 0
}

# Show usage
show_usage() {
    cat <<EOF
Usage: $(basename "$0") [OPTIONS] FILE_OR_DIR...

Scan Bash scripts for PATH manipulation vulnerabilities.

OPTIONS:
  -h, --help        Show this help message
  -v, --verbose     Verbose output
  -r, --recursive   Scan directories recursively

EXAMPLES:
  # Scan a single file
  $(basename "$0") script.sh
  
  # Scan multiple files
  $(basename "$0") script1.sh script2.sh
  
  # Scan directory recursively
  $(basename "$0") -r /path/to/scripts
  
  # Scan current directory
  $(basename "$0") -r .
EOF
}

# Main scanning function
main() {
    local recursive=false
    local targets=()
    
    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -h|--help)
                show_usage
                exit 0
                ;;
            -v|--verbose)
                set -x
                shift
                ;;
            -r|--recursive)
                recursive=true
                shift
                ;;
            -*)
                echo "Error: Unknown option: $1" >&2
                show_usage
                exit 1
                ;;
            *)
                targets+=("$1")
                shift
                ;;
        esac
    done
    
    # Check we have targets
    if [[ ${#targets[@]} -eq 0 ]]; then
        echo "Error: No files or directories specified" >&2
        show_usage
        exit 1
    fi
    
    echo "Scanning for PATH vulnerabilities..."
    echo ""
    
    # Process each target
    for target in "${targets[@]}"; do
        if [[ -f "$target" ]]; then
            scan_file "$target"
        elif [[ -d "$target" ]]; then
            if $recursive; then
                while IFS= read -r -d '' file; do
                    scan_file "$file"
                done < <(find "$target" -type f -name "*.sh" -print0)
            else
                echo "Error: $target is a directory. Use -r to scan recursively." >&2
                exit 1
            fi
        else
            echo "Error: Not found: $target" >&2
            exit 1
        fi
    done
    
    # Summary
    echo "================================"
    echo "Scan complete"
    echo "Files scanned: $TOTAL_FILES"
    echo "Vulnerable files: $VULNERABLE_FILES"
    echo "Total issues: $TOTAL_ISSUES"
    
    if [[ $TOTAL_ISSUES -eq 0 ]]; then
        echo -e "${GREEN}No vulnerabilities found!${NC}"
        exit 0
    else
        echo -e "${RED}Found $TOTAL_ISSUES potential vulnerabilities${NC}"
        exit 1
    fi
}

main "$@"
