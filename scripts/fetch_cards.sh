#!/bin/bash

# Base API endpoint to get all card details
base_url="https://digimoncard.io/api-public/getAllCards.php?sort=name&series=Digimon%20Card%20Game&sortdirection=asc"

# Directory to store card data by prefix and error logs
output_dir="card_data"
error_dir="$output_dir/errors"
mkdir -p "$output_dir"
mkdir -p "$error_dir"

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

# Check if jq is installed
if ! command -v jq &> /dev/null; then
    echo -e "${RED}Error: jq is required but not installed. Please install jq to run this script.${NC}"
    exit 1
fi

# Check if all_cards.json exists
all_cards_file="$output_dir/all_cards.json"
temp_all_cards_file="$output_dir/new_all_cards.json"
diff_card_numbers=()

if [ -f "$all_cards_file" ]; then
    print_header "Fetching all cards from API and comparing with existing data"
    curl --location "$base_url" -o "$temp_all_cards_file"
    
    # Iterate through each card in the new file
    while read -r card; do
        card_number=$(echo "$card" | jq -r '.cardnumber')
        prefix=$(echo "$card_number" | cut -d'-' -f1)
        prefix_file="$output_dir/${prefix}.json"
        
        # Check if the prefix file exists and if the card exists in that file
        if [ -f "$prefix_file" ]; then

            card_exists=$(jq --arg card_number "$card_number" 'any(.[]; .id == $card_number)' "$prefix_file")

            echo -e "${GREEN}Checking card number $card_number in $prefix_file${NC}"
            # print card_exists value for debugging
            echo -e "${GREEN}Card exists: $card_exists${NC}"
            if [ "$card_exists" != "true" ]; then
                # This card is new or updated, so it needs processing
                echo -e "${YELLOW}============================================================${NC}"
                echo -e "${YELLOW}Card number $card_number is new or updated.${NC}"
                echo -e "${YELLOW}Card name: $(echo "$card" | jq -r '.name')${NC}"
                echo -e "${YELLOW}============================================================${NC}"
                diff_card_numbers+=("$card_number")
            else 
                # This card already exists in the prefix file
                echo -e "${GREEN}Card number $card_number already exists in $prefix_file. Skipping.${NC}"
            fi
        else
            # The prefix file does not exist, so this card needs processing
            echo -e "${YELLOW}Prefix file $prefix_file does not exist.${NC}"
            diff_card_numbers+=("$card_number")
        fi
    done < <(jq -c '.[]' "$temp_all_cards_file")
    echo -e "${GREEN}Finished comparing all cards.${NC}"
    # Print the card numbers length of array that need processing
    echo -e "${YELLOW}Card numbers that need processing:${NC} ${#diff_card_numbers[@]}"

    # Check if any new or changed card numbers were found
    if [ ${#diff_card_numbers[@]} -eq 0 ]; then
        echo -e "${GREEN}No new cards found. Exiting.${NC}"
        rm "$temp_all_cards_file" # Clean up
        exit 0
    else
        echo -e "${CYAN}New or changed cards detected. Processing...${NC}"
        mv "$temp_all_cards_file" "$all_cards_file" # Replace old file with new data
    fi
else
    # If all_cards.json doesn't exist, fetch and save it
    print_header "Fetching all cards from API"
    curl --location "$base_url" -o "$all_cards_file"
    echo -e "${GREEN}Saved fetched data to: ${all_cards_file}${NC}"

    # Get all card numbers from the new file
    diff_card_numbers=($(jq -r '.[].cardnumber' "$all_cards_file"))
fi

# Loop through each new or changed card number and fetch detailed data
for card_number in "${diff_card_numbers[@]}"; do
    print_header "Processing card number: $card_number"
    prefix=$(echo "$card_number" | cut -d'-' -f1)

    # Create a master file for the prefix if it doesn't exist
    master_file="$output_dir/$prefix.json"
    file_existed=false
    if [ -f "$master_file" ]; then
        file_existed=true
        echo -e "${YELLOW}Master file ${master_file} already exists.${NC}"
    else
        echo "[]" > "$master_file" # Initialize as an empty JSON array
        echo -e "${GREEN}Created new master file: ${master_file}${NC}"
    fi

    # Construct URL for fetching detailed info about each card
    card_url="https://digimoncard.io/api-public/search.php?card=$card_number"

    # Fetch card details and store in a variable
    echo -e "${CYAN}Fetching details for card number: $card_number${NC}"
    card_data=$(curl --silent --location "$card_url")

    # Check if card data is valid JSON
    if [ "$card_data" != "null" ] && [ -n "$card_data" ] && echo "$card_data" | jq . > /dev/null 2>&1; then
        if echo "$card_data" | jq 'type == "array"' > /dev/null 2>&1; then
            card_data=$(echo "$card_data" | jq '.[0]')
        fi

        # Ensure the script exits on any error
        set -e

        # Extract keywords from the card data
        keywords=()

        # Extract multi-word keywords enclosed in square brackets and count as one keyword
        echo "Extracting keywords enclosed in square brackets..."
        square_bracket_keywords=$(echo "$card_data" | grep -o '\[[^]]*\]' | sed 's/^\[\(.*\)\]$/\1/')

        # Add keywords to the array if not already present
        if [ -n "$square_bracket_keywords" ]; then
            while read -r keyword; do
                if [[ ! " ${keywords[*]} " =~ " ${keyword} " ]]; then
                    keywords+=("$keyword")
                    echo "Keyword being added: '$keyword'" # Debugging line
                fi
            done <<< "$(printf '%s\n' "$square_bracket_keywords")"
        fi

        # Extract multi-word keywords enclosed in angle brackets and count as one keyword
        echo "Extracting keywords enclosed in angle brackets..."
        angle_bracket_keywords=$(echo "$card_data" | grep -o '＜[^＞]*＞' | sed 's/^＜\(.*\)＞$/\1/')

        # Add keywords to the array if not already present
        if [ -n "$angle_bracket_keywords" ]; then
            while read -r keyword; do
                if [[ ! " ${keywords[*]} " =~ " ${keyword} " ]]; then
                    keywords+=("$keyword")
                    echo "Keyword being added: '$keyword'" # Debugging line
                fi
            done <<< "$(printf '%s\n' "$angle_bracket_keywords")"
        fi

        # Print the entire keywords array for debugging
        echo "Full keywords array: $(IFS=,; echo "${keywords[*]}")"

        # Add keywords to card data as a new "keywords" field
        if [ ${#keywords[@]} -gt 0 ]; then
            keywords_json=$(printf '%s\n' "${keywords[@]}" | jq -R . | jq -s .)
            keywords_count=${#keywords[@]}
        else
            keywords_json="[]"
            keywords_count=0
        fi
        card_data=$(echo "$card_data" | jq --argjson keywords "$keywords_json" --argjson keywords_count "$keywords_count" '. + {keywords: $keywords, keywords_count: $keywords_count}')

        # Count and collect certain properties
        attributes=("digi_type" "digi_type1" "digi_type2" "digi_type3" "digi_type4" "digi_type5" "digi_type6" "form" "attribute" "stage" "type")
        attribute_keywords=()
        attribute_count=0

        for attribute in "${attributes[@]}"; do
            value=$(echo "$card_data" | jq -r --arg attribute "$attribute" '.[$attribute] // empty')
            if [ -n "$value" ] && [ "$value" != "null" ]; then
                # Check if the value is already in the attribute_keywords array
                if [[ ! " ${attribute_keywords[*]} " =~ " ${value} " ]]; then
                    attribute_keywords+=("$value")
                    ((attribute_count++))
                fi
            fi
        done

        # Convert attribute_keywords to a JSON array
        attribute_keywords_json=$(printf '%s\n' "${attribute_keywords[@]}" | jq -R . | jq -s .)

        # Add attribute_count and attribute_keywords to the card data
        card_data=$(echo "$card_data" | jq --argjson attribute_keywords "$attribute_keywords_json" --argjson attribute_count "$attribute_count" '. + {attribute_count: $attribute_count, attribute_keywords: $attribute_keywords}')

        # Print the added attributes for debugging
        echo "Unique attributes found: ${attribute_keywords[@]}"
        echo "Unique attribute count: $attribute_count"

        # Log card data
        echo -e "${MAGENTA}Processed card data with keywords:${NC} $card_data"

        # Check if the card already exists in the master file
        if ! jq -e --arg card_number "$card_number" '.[] | select(.cardnumber == $card_number)' "$master_file" > /dev/null; then
            echo -e "${GREEN}Appending new card data for: $card_number${NC}"
            if jq ". += [$card_data]" "$master_file" | jq 'sort_by(.id)' > "$master_file.tmp"; then
                mv "$master_file.tmp" "$master_file"
                echo -e "${GREEN}Appended card number: $card_number to $master_file${NC}"
            else
                error_message="Error appending data for card number: $card_number"
                echo -e "${RED}${error_message}${NC}"
                error_log_file="$error_dir/error_$(date +'%Y-%m-%d_%H-%M-%S').json"
                existing_content=$(cat "$master_file")

                # Save error details to a JSON file
                jq -n \
                    --arg card_number "$card_number" \
                    --arg card_data "$card_data" \
                    --arg master_file "$master_file" \
                    --arg existing_content "$existing_content" \
                    --arg file_existed "$file_existed" \
                    --arg error_message "$error_message" \
                    '{
                        timestamp: now | todate,
                        card_number: $card_number,
                        card_data: $card_data,
                        master_file: $master_file,
                        file_existed: ($file_existed | test("true")),
                        existing_content: $existing_content,
                        error_message: $error_message
                    }' > "$error_log_file"

                echo -e "${YELLOW}Error details saved to ${error_log_file}${NC}"
                exit 1
            fi
        else
            echo -e "${YELLOW}Duplicate found: $card_number already exists in $master_file. Skipping.${NC}"
        fi
    else
        echo -e "${RED}Card number $card_number data is null, empty, or not an object. Skipping.${NC}"
        error_message="Card data for $card_number is null, empty, or not an object"
        error_log_file="$error_dir/error_$(date +'%Y-%m-%d_%H-%M-%S').json"

        # Save error details for null, empty, or non-object data
        jq -n \
            --arg card_number "$card_number" \
            --arg card_data "$card_data" \
            --arg master_file "$master_file" \
            --arg file_existed "$file_existed" \
            --arg error_message "$error_message" \
            '{
                timestamp: now | todate,
                card_number: $card_number,
                card_data: $card_data,
                master_file: $master_file,
                file_existed: ($file_existed | test("true")),
                error_message: $error_message
            }' > "$error_log_file"

        echo -e "${YELLOW}Error details saved to ${error_log_file}${NC}"
        exit 1
    fi

    # Wait for a random time between 4 and 8 seconds to prevent rate limiting
    sleep $((RANDOM % 5 + 4))
done

print_header "All card data has been processed and logged"
