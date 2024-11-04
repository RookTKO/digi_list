#!/bin/bash

# Directory to store output keyword files
output_dir="keyword_relationships"
mkdir -p "$output_dir"

# ANSI color codes for formatting
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
NC='\033[0m' # No color

# Function to print a header with color and ASCII separators
print_header() {
    echo -e "${MAGENTA}============================================================${NC}"
    echo -e "${CYAN}$1${NC}"
    echo -e "${MAGENTA}============================================================${NC}"
}

# Start processing all JSON files except all_cards.json
print_header "Starting keyword relationship extraction"
for file in card_data/*.json; do
    if [[ -f "$file" && "$(basename "$file")" != "all_cards.json" ]]; then
        echo -e "${GREEN}Processing file: ${file}${NC}"
        prefix=$(basename "$file" .json)

        # Iterate through each card object in the JSON file
        jq -c '.[]' "$file" | while read -r card; do
            card_id=$(echo "$card" | jq -r '.id')
            main_effect=$(echo "$card" | jq -r '.main_effect')
            source_effect=$(echo "$card" | jq -r '.source_effect')
            alt_effect=$(echo "$card" | jq -r '.alt_effect')

            echo -e "${YELLOW}Processing card ID: ${card_id}${NC}"

            # Check for symbols or keywords and save the ID to relevant files
            for effect in "$main_effect" "$source_effect" "$alt_effect"; do
                if [[ "$effect" =~ [＜＞] ]]; then
                    # Extract the first word from the match
                    keyword=$(echo "$effect" | grep -o '＜[^＞]*＞' | head -n 1 | sed 's/＜\([^＞]*\)＞/\1/' | awk '{print $1}')
                    if [ -n "$keyword" ]; then
                        echo "$card_id" >> "$output_dir/${keyword}.txt"
                        echo -e "${CYAN}Added to ${keyword}.txt${NC}"
                    fi
                fi
                
                if [[ "$effect" =~ \[[^]]+\] ]]; then
                    # Extract the first word from the match
                    keyword=$(echo "$effect" | grep -o '\[[^]]*\]' | head -n 1 | sed 's/\[\([^]]*\)\]/\1/' | awk '{print $1}')
                    if [ -n "$keyword" ]; then
                        echo "$card_id" >> "$output_dir/${keyword}.txt"
                        echo -e "${CYAN}Added to ${keyword}.txt${NC}"
                    fi
                fi
            done

            # Check other card object parameters
            for key in "stage" "color" "evolution_color" "evolution_cost" "play_cost" "level" "dp" "attribute"; do
                value=$(echo "$card" | jq -r ".$key" | tr ' ' '_')
                if [ "$value" != "null" ] && [ -n "$value" ]; then
                    echo "$card_id" >> "$output_dir/${key}_${value}.txt"
                    echo -e "${CYAN}Added to ${key}_${value}.txt${NC}"
                fi
            done

            # Iterate for multiple color and digi_type parameters
            for i in {2..8}; do
                color_key="color$i"
                digi_type_key="digi_type$i"

                color_value=$(echo "$card" | jq -r ".$color_key" | tr ' ' '_')
                digi_type_value=$(echo "$card" | jq -r ".$digi_type_key" | tr ' ' '_')

                if [ "$color_value" != "null" ] && [ -n "$color_value" ]; then
                    echo "$card_id" >> "$output_dir/color_${color_value}.txt"
                    echo -e "${CYAN}Added to color_${color_value}.txt${NC}"
                fi

                if [ "$digi_type_value" != "null" ] && [ -n "$digi_type_value" ]; then
                    echo "$card_id" >> "$output_dir/digi_type_${digi_type_value}.txt"
                    echo -e "${CYAN}Added to digi_type_${digi_type_value}.txt${NC}"
                fi
            done

            echo -e "${YELLOW}Finished processing card ID: ${card_id}${NC}"
        done

        echo -e "${GREEN}Finished processing file: ${file}${NC}"
    else
        echo -e "${RED}Skipping file: ${file}${NC}"
    fi
done

print_header "Keyword relationship extraction completed"
