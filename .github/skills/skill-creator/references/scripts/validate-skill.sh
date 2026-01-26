#!/usr/bin/env bash
# Validate skill format and content
# Checks that a skill follows the required structure

set -euo pipefail

# Colors
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly NC='\033[0m'

# Get skills directory
SKILLS_DIR="${SKILLS_DIR:-.github/skills}"

# Counters
ERRORS=0
WARNINGS=0
CHECKS=0

# Check and report
check() {
    local message="$1"
    local status="$2"
    
    CHECKS=$((CHECKS + 1))
    
    if [[ "$status" == "pass" ]]; then
        echo -e "${GREEN}✓${NC} $message"
    elif [[ "$status" == "fail" ]]; then
        echo -e "${RED}✗${NC} $message"
        ERRORS=$((ERRORS + 1))
    elif [[ "$status" == "warn" ]]; then
        echo -e "${YELLOW}⚠${NC} $message"
        WARNINGS=$((WARNINGS + 1))
    fi
}

# Validate skill
validate_skill() {
    local skill_name="$1"
    local skill_dir="$SKILLS_DIR/$skill_name"
    local skill_file="$skill_dir/SKILL.md"
    
    echo "Validating skill: $skill_name"
    echo ""
    
    # Check directory exists
    if [[ ! -d "$skill_dir" ]]; then
        check "Skill directory exists" "fail"
        echo ""
        echo "Directory not found: $skill_dir"
        return 1
    fi
    check "Skill directory exists" "pass"
    
    # Check SKILL.md exists
    if [[ ! -f "$skill_file" ]]; then
        check "SKILL.md exists" "fail"
        echo ""
        echo "SKILL.md not found: $skill_file"
        return 1
    fi
    check "SKILL.md exists" "pass"
    
    # Check frontmatter
    if head -n 1 "$skill_file" | grep -q "^---$"; then
        check "Frontmatter delimiter present" "pass"
    else
        check "Frontmatter delimiter present" "fail"
    fi
    
    # Check name in frontmatter
    if grep -q "^name: " "$skill_file"; then
        check "Frontmatter has 'name' field" "pass"
        
        # Validate name format
        local frontmatter_name
        frontmatter_name=$(grep "^name: " "$skill_file" | head -n 1 | cut -d: -f2- | xargs)
        
        if [[ "$frontmatter_name" =~ ^[a-z0-9]+(-[a-z0-9]+)*$ ]]; then
            check "Name is in kebab-case" "pass"
        else
            check "Name is in kebab-case (got: $frontmatter_name)" "fail"
        fi
        
        if [[ "$frontmatter_name" == "$skill_name" ]]; then
            check "Name matches directory name" "pass"
        else
            check "Name matches directory name (got: $frontmatter_name, expected: $skill_name)" "warn"
        fi
    else
        check "Frontmatter has 'name' field" "fail"
    fi
    
    # Check description in frontmatter
    if grep -q "^description: " "$skill_file"; then
        check "Frontmatter has 'description' field" "pass"
        
        local description
        description=$(grep "^description: " "$skill_file" | cut -d: -f2- | xargs)
        
        if [[ ${#description} -gt 20 ]]; then
            check "Description is descriptive (${#description} chars)" "pass"
        else
            check "Description is too short (${#description} chars)" "warn"
        fi
        
        if echo "$description" | grep -qi "trigger"; then
            check "Description includes trigger patterns" "pass"
        else
            check "Description includes trigger patterns" "warn"
        fi
    else
        check "Frontmatter has 'description' field" "fail"
    fi
    
    # Check content sections
    if grep -q "^# " "$skill_file"; then
        check "Has main heading" "pass"
    else
        check "Has main heading" "warn"
    fi
    
    if grep -q "^## Purpose" "$skill_file"; then
        check "Has Purpose section" "pass"
    else
        check "Has Purpose section" "warn"
    fi
    
    if grep -q "^## " "$skill_file" | head -n 3 > /dev/null; then
        local section_count
        section_count=$(grep -c "^## " "$skill_file")
        check "Has multiple sections ($section_count sections)" "pass"
    else
        check "Has multiple sections" "warn"
    fi
    
    # Check for code examples
    if grep -q "^\`\`\`" "$skill_file"; then
        check "Contains code examples" "pass"
    else
        check "Contains code examples" "warn"
    fi
    
    # Check references directory
    if [[ -d "$skill_dir/references" ]]; then
        check "Has references directory" "pass"
        
        # Check for templates.md
        if [[ -f "$skill_dir/references/templates.md" ]]; then
            check "Has references/templates.md" "pass"
        fi
        
        # Check for broken reference links
        local refs
        refs=$(grep -o "references/[^)]*" "$skill_file" 2>/dev/null || true)
        
        if [[ -n "$refs" ]]; then
            local broken=0
            while IFS= read -r ref; do
                if [[ ! -f "$skill_dir/$ref" ]]; then
                    check "Reference exists: $ref" "fail"
                    broken=$((broken + 1))
                fi
            done <<< "$refs"
            
            if [[ $broken -eq 0 ]]; then
                check "All reference links valid" "pass"
            fi
        fi
    fi
    
    # Check file size (should have substance)
    local size
    size=$(wc -c < "$skill_file")
    
    if [[ $size -gt 1000 ]]; then
        check "File has substantial content (${size} bytes)" "pass"
    elif [[ $size -gt 500 ]]; then
        check "File has some content (${size} bytes)" "warn"
    else
        check "File is very short (${size} bytes)" "warn"
    fi
    
    return 0
}

# Show usage
show_usage() {
    cat <<EOF
Usage: $(basename "$0") SKILL_NAME [SKILL_NAME...]

Validate one or more skills.

Examples:
  $(basename "$0") bash-library-template
  $(basename "$0") handle-state github-issues
  $(basename "$0") --all
EOF
}

# Main
main() {
    if [[ $# -eq 0 ]]; then
        show_usage
        exit 1
    fi
    
    if [[ "$1" == "--help" ]] || [[ "$1" == "-h" ]]; then
        show_usage
        exit 0
    fi
    
    # Validate all skills if --all
    if [[ "$1" == "--all" ]]; then
        echo "Validating all skills..."
        echo ""
        
        for skill_dir in "$SKILLS_DIR"/*; do
            if [[ -d "$skill_dir" ]]; then
                local skill_name
                skill_name=$(basename "$skill_dir")
                validate_skill "$skill_name"
                echo ""
            fi
        done
    else
        # Validate specified skills
        for skill_name in "$@"; do
            validate_skill "$skill_name"
            echo ""
        done
    fi
    
    # Summary
    echo "================================"
    echo "Validation complete"
    echo "Checks: $CHECKS"
    echo "Errors: $ERRORS"
    echo "Warnings: $WARNINGS"
    
    if [[ $ERRORS -eq 0 ]]; then
        echo -e "${GREEN}Validation passed!${NC}"
        exit 0
    else
        echo -e "${RED}Validation failed with $ERRORS errors${NC}"
        exit 1
    fi
}

main "$@"
