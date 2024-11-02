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

# Fetch all cards and save as all_cards.json
print_header "Fetching all cards from API"
curl --location "$base_url" -o "$output_dir/all_cards.json"
echo -e "${GREEN}Saved fetched data to: ${output_dir}/all_cards.json${NC}"

# Check if jq is installed
if ! command -v jq &> /dev/null; then
    echo -e "${RED}Error: jq is required but not installed. Please install jq to run this script.${NC}"
    exit 1
fi

# Extract card numbers from the JSON response using jq
card_numbers=$(jq -r '.[].cardnumber' "$output_dir/all_cards.json")

# Loop through each card number and fetch its detailed data
for card_number in $card_numbers; do
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

        # Log card data
        echo -e "${MAGENTA}Processed card data:${NC} $card_data"

        # Check if the card already exists in the master file
        if ! jq -e --arg card_number "$card_number" '.[] | select(.cardnumber == $card_number)' "$master_file" > /dev/null; then
            echo -e "${GREEN}Appending new card data for: $card_number${NC}"
            if jq ". += [$card_data]" "$master_file" > "$master_file.tmp"; then
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
    fi

    # Wait for a random time between 4 and 8 seconds to prevent rate limiting
    sleep $((RANDOM % 5 + 4))
done

print_header "All card data has been processed and logged"
