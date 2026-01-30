#!/usr/bin/env bash
# Interactive skill creator
# Creates a new skill with proper structure and templates

set -euo pipefail

# Colors
readonly GREEN='\033[0;32m'
readonly BLUE='\033[0;34m'
readonly YELLOW='\033[1;33m'
readonly NC='\033[0m'

# Get the skills directory
SKILLS_DIR="${SKILLS_DIR:-.github/skills}"

# Skill templates
declare -A SKILL_TYPES=(
    ["tool"]="Tool/Library Skill - Documents a specific tool or library"
    ["template"]="Template Skill - Provides scaffolding for creating components"
    ["process"]="Process/Workflow Skill - Guides through a workflow"
    ["security"]="Security Skill - Identifies and fixes security issues"
    ["minimal"]="Minimal Skill - Simple, focused guidance"
)

# Prompt for input
prompt() {
    local prompt_text="$1"
    local default="${2:-}"
    local result
    
    if [[ -n "$default" ]]; then
        read -rp "$(echo -e "${BLUE}${prompt_text}${NC} [${default}]: ")" result
        echo "${result:-$default}"
    else
        read -rp "$(echo -e "${BLUE}${prompt_text}${NC}: ")" result
        echo "$result"
    fi
}

# Show skill type menu
show_skill_types() {
    echo -e "${GREEN}Available skill types:${NC}"
    echo ""
    local i=1
    for type in "${!SKILL_TYPES[@]}"; do
        echo "  $i) $type - ${SKILL_TYPES[$type]}"
        ((i++))
    done
    echo ""
}

# Convert name to kebab-case
to_kebab_case() {
    local input="$1"
    echo "$input" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9]/-/g' | sed 's/--*/-/g' | sed 's/^-//;s/-$//'
}

# Create skill directory structure
create_structure() {
    local skill_name="$1"
    local skill_dir="$SKILLS_DIR/$skill_name"
    
    if [[ -d "$skill_dir" ]]; then
        echo -e "${YELLOW}Warning: Skill directory already exists: $skill_dir${NC}"
        local overwrite
        overwrite=$(prompt "Overwrite?" "n")
        if [[ "$overwrite" != "y" ]]; then
            echo "Aborted."
            return 1
        fi
        rm -rf "$skill_dir"
    fi
    
    mkdir -p "$skill_dir/references/scripts"
    echo -e "${GREEN}✓${NC} Created directory structure"
}

# Generate SKILL.md
generate_skill_md() {
    local skill_name="$1"
    local skill_title="$2"
    local description="$3"
    local skill_type="$4"
    local skill_file="$SKILLS_DIR/$skill_name/SKILL.md"
    
    cat > "$skill_file" <<EOF
---
name: $skill_name
description: $description
---

# $skill_title

## Purpose

[Explain what this skill does and why it exists]

## Quick Start

\`\`\`bash
# Minimal example
\`\`\`

## Main Content

### Section 1

[Core guidance]

### Section 2

[Additional information]

## Examples

### Example 1

\`\`\`bash
# Code example
\`\`\`

## Reference

- [templates.md](references/templates.md) - Code templates

## Tips

- Tip 1
- Tip 2
EOF

    echo -e "${GREEN}✓${NC} Created SKILL.md"
}

# Generate references/templates.md
generate_templates() {
    local skill_name="$1"
    local templates_file="$SKILLS_DIR/$skill_name/references/templates.md"
    
    cat > "$templates_file" <<EOF
# Templates

## Template 1

\`\`\`bash
# Template code
\`\`\`

## Template 2

\`\`\`bash
# Another template
\`\`\`
EOF

    echo -e "${GREEN}✓${NC} Created references/templates.md"
}

# Generate README for references
generate_references_readme() {
    local skill_name="$1"
    local readme_file="$SKILLS_DIR/$skill_name/references/README.md"
    
    cat > "$readme_file" <<EOF
# Reference Materials for $skill_name

This directory contains supporting materials for the $skill_name skill.

## Files

- \`templates.md\` - Code templates
- \`examples.md\` - Detailed examples (if needed)
- \`scripts/\` - Helper scripts (if needed)
EOF

    echo -e "${GREEN}✓${NC} Created references/README.md"
}

# Main function
main() {
    echo -e "${GREEN}=== Skill Creator ===${NC}"
    echo ""
    
    # Get skill name
    local skill_name_input
    skill_name_input=$(prompt "Skill name (will be converted to kebab-case)")
    
    if [[ -z "$skill_name_input" ]]; then
        echo "Error: Skill name is required"
        exit 1
    fi
    
    local skill_name
    skill_name=$(to_kebab_case "$skill_name_input")
    
    echo "Kebab-case name: $skill_name"
    echo ""
    
    # Get skill title (for display)
    local skill_title
    skill_title=$(prompt "Skill title (for heading)" "$skill_name_input")
    
    # Get description
    echo ""
    echo "Description should include:"
    echo "  - What the skill provides"
    echo "  - When to use it"
    echo "  - Trigger phrases (e.g., 'Triggers on \"create X\"')"
    echo ""
    
    local description
    description=$(prompt "Description")
    
    if [[ -z "$description" ]]; then
        echo "Error: Description is required"
        exit 1
    fi
    
    # Get skill type
    echo ""
    show_skill_types
    local skill_type
    skill_type=$(prompt "Skill type" "minimal")
    
    # Create the skill
    echo ""
    echo -e "${GREEN}Creating skill: $skill_name${NC}"
    echo ""
    
    create_structure "$skill_name" || exit 1
    generate_skill_md "$skill_name" "$skill_title" "$description" "$skill_type"
    generate_templates "$skill_name"
    generate_references_readme "$skill_name"
    
    echo ""
    echo -e "${GREEN}=== Skill created successfully! ===${NC}"
    echo ""
    echo "Location: $SKILLS_DIR/$skill_name"
    echo ""
    echo "Next steps:"
    echo "  1. Edit $SKILLS_DIR/$skill_name/SKILL.md"
    echo "  2. Add templates to references/templates.md"
    echo "  3. Add examples if needed"
    echo "  4. Test the skill"
    echo ""
    echo "Validate with: ./validate-skill.sh $skill_name"
}

main "$@"
