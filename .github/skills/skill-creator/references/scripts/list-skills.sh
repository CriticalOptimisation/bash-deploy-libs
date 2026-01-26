#!/usr/bin/env bash
# List all skills with metadata
# Displays skill names, descriptions, and status

set -euo pipefail

# Colors
readonly BLUE='\033[0;34m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly NC='\033[0m'

# Get skills directory
SKILLS_DIR="${SKILLS_DIR:-.github/skills}"

# Extract frontmatter field
get_frontmatter_field() {
    local file="$1"
    local field="$2"
    
    # Extract YAML frontmatter and get field
    awk -v field="$field" '
        BEGIN { in_fm=0; found=0 }
        /^---$/ { 
            in_fm++; 
            if(in_fm > 1) exit;
            next 
        }
        in_fm == 1 && $1 == field":" { 
            $1=""; 
            gsub(/^ */, ""); 
            print; 
            found=1;
            exit 
        }
    ' "$file"
}

# List skills
list_skills() {
    local format="${1:-table}"
    
    if [[ "$format" == "table" ]]; then
        echo -e "${GREEN}Available Skills${NC}"
        echo ""
        printf "%-30s %-60s\n" "Skill" "Description"
        printf "%-30s %-60s\n" "-----" "-----------"
    fi
    
    for skill_dir in "$SKILLS_DIR"/*; do
        if [[ ! -d "$skill_dir" ]]; then
            continue
        fi
        
        local skill_name
        skill_name=$(basename "$skill_dir")
        
        local skill_file="$skill_dir/SKILL.md"
        
        if [[ ! -f "$skill_file" ]]; then
            if [[ "$format" == "table" ]]; then
                printf "%-30s ${YELLOW}%-60s${NC}\n" "$skill_name" "[SKILL.md not found]"
            fi
            continue
        fi
        
        local description
        description=$(get_frontmatter_field "$skill_file" "description")
        
        if [[ -z "$description" ]]; then
            description="[No description]"
        fi
        
        # Truncate long descriptions
        if [[ ${#description} -gt 60 ]] && [[ "$format" == "table" ]]; then
            description="${description:0:57}..."
        fi
        
        if [[ "$format" == "table" ]]; then
            printf "%-30s %-60s\n" "$skill_name" "$description"
        elif [[ "$format" == "names" ]]; then
            echo "$skill_name"
        elif [[ "$format" == "json" ]]; then
            echo "{\"name\":\"$skill_name\",\"description\":\"$description\"}"
        fi
    done
    
    if [[ "$format" == "table" ]]; then
        echo ""
        local count
        count=$(find "$SKILLS_DIR" -mindepth 1 -maxdepth 1 -type d | wc -l)
        echo "Total skills: $count"
    fi
}

# Show detailed info for a skill
show_skill_info() {
    local skill_name="$1"
    local skill_dir="$SKILLS_DIR/$skill_name"
    local skill_file="$skill_dir/SKILL.md"
    
    if [[ ! -f "$skill_file" ]]; then
        echo "Error: Skill not found: $skill_name"
        return 1
    fi
    
    echo -e "${GREEN}Skill: $skill_name${NC}"
    echo ""
    
    local name desc
    name=$(get_frontmatter_field "$skill_file" "name")
    desc=$(get_frontmatter_field "$skill_file" "description")
    
    echo "Name: $name"
    echo "Description: $desc"
    echo ""
    echo "Location: $skill_dir"
    
    # Check for references
    if [[ -d "$skill_dir/references" ]]; then
        echo ""
        echo "References:"
        for ref_file in "$skill_dir/references"/*; do
            if [[ -f "$ref_file" ]]; then
                echo "  - $(basename "$ref_file")"
            fi
        done
        
        if [[ -d "$skill_dir/references/scripts" ]]; then
            echo ""
            echo "Scripts:"
            for script in "$skill_dir/references/scripts"/*; do
                if [[ -f "$script" ]]; then
                    echo "  - $(basename "$script")"
                fi
            done
        fi
    fi
    
    # File size
    local size
    size=$(wc -c < "$skill_file")
    echo ""
    echo "Size: $size bytes"
    
    # Line count
    local lines
    lines=$(wc -l < "$skill_file")
    echo "Lines: $lines"
    
    # Section count
    local sections
    sections=$(grep -c "^## " "$skill_file" || true)
    echo "Sections: $sections"
}

# Show usage
show_usage() {
    cat <<EOF
Usage: $(basename "$0") [OPTIONS] [SKILL_NAME]

List available skills or show details about a specific skill.

OPTIONS:
  -h, --help         Show this help message
  -f, --format FMT   Output format: table (default), names, json
  -i, --info NAME    Show detailed info about a skill

EXAMPLES:
  # List all skills
  $(basename "$0")
  
  # List skill names only
  $(basename "$0") --format names
  
  # Show skill details
  $(basename "$0") --info bash-library-template
EOF
}

# Main
main() {
    local format="table"
    local show_info=""
    
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -h|--help)
                show_usage
                exit 0
                ;;
            -f|--format)
                format="$2"
                shift 2
                ;;
            -i|--info)
                show_info="$2"
                shift 2
                ;;
            *)
                show_info="$1"
                shift
                ;;
        esac
    done
    
    if [[ -n "$show_info" ]]; then
        show_skill_info "$show_info"
    else
        list_skills "$format"
    fi
}

main "$@"
