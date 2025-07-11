#!/bin/bash

# Shell script to extract stopped apps older than 60 days from CF API JSON output
# Usage: ./extract-old-stopped-apps.sh -o "old_stopped_apps.csv"

# Function to display usage
show_usage() {
    echo "Usage: $0 -o <output_csv_file>"
    echo "Example: $0 -o 'old_stopped_apps.csv'"
}

# Initialize variables
OUTPUT_FILE=""

# Parse command line arguments
while getopts "o:h" opt; do
    case $opt in
        o)
            OUTPUT_FILE="$OPTARG"
            ;;
        h)
            show_usage
            exit 0
            ;;
        \?)
            echo "Invalid option: -$OPTARG" >&2
            show_usage
            exit 1
            ;;
    esac
done

# Check if required parameters are provided
if [[ -z "$OUTPUT_FILE" ]]; then
    echo "Error: Output file must be specified" >&2
    show_usage
    exit 1
fi

# Check if jq is installed
if ! command -v jq &> /dev/null; then
    echo "Error: jq is required but not installed. Please install jq first." >&2
    exit 1
fi

# Check if cf CLI is installed and logged in
if ! command -v cf &> /dev/null; then
    echo "Error: cf CLI is required but not installed. Please install cf CLI first." >&2
    exit 1
fi

# Test CF API access
if ! cf curl "/v3/info" &> /dev/null; then
    echo "Error: Unable to access CF API. Please ensure you're logged in with 'cf login'" >&2
    exit 1
fi

# Calculate the date 60 days ago (Unix timestamp)
# Compatible with both Linux and macOS/BSD
if date -v-60d >/dev/null 2>&1; then
    # macOS/BSD date
    SIXTY_DAYS_AGO=$(date -v-60d -u +%s)
    SIXTY_DAYS_AGO_STRING=$(date -v-60d -u +"%Y-%m-%dT%H:%M:%SZ")
else
    # Linux date
    SIXTY_DAYS_AGO=$(date -d "60 days ago" -u +%s)
    SIXTY_DAYS_AGO_STRING=$(date -d "60 days ago" -u +"%Y-%m-%dT%H:%M:%SZ")
fi

echo "Filtering apps stopped and updated before: $SIXTY_DAYS_AGO_STRING"

# Create temporary files for processing
TEMP_DIR=$(mktemp -d)
TEMP_RESULTS="$TEMP_DIR/results.json"

# Cleanup function
cleanup() {
    rm -rf "$TEMP_DIR"
}
trap cleanup EXIT

# Fetch apps data using cf curl
echo "Fetching apps data using cf curl..."
APPS_JSON=$(cf curl "/v3/apps?per_page=5000")
if [[ -z "$APPS_JSON" ]]; then
    echo "Error: Failed to fetch apps data from CF API" >&2
    exit 1
fi

# Fetch spaces data using cf curl
echo "Fetching spaces data using cf curl..."
SPACES_JSON=$(cf curl "/v3/spaces?per_page=5000")
if [[ -z "$SPACES_JSON" ]]; then
    echo "Error: Failed to fetch spaces data from CF API" >&2
    exit 1
fi

# Fetch organizations data using cf curl
echo "Fetching organizations data using cf curl..."
ORGS_JSON=$(cf curl "/v3/organizations?per_page=5000")
if [[ -z "$ORGS_JSON" ]]; then
    echo "Error: Failed to fetch organizations data from CF API" >&2
    exit 1
fi

# Process the data using jq
echo "Processing applications..."

# Create a lookup table for organization information
if ! ORG_LOOKUP=$(echo "$ORGS_JSON" | jq -r '.resources | map({(.guid): .name}) | add' 2>/dev/null); then
    echo "Error: Failed to process organizations data" >&2
    exit 1
fi

# Create a lookup table for space information
if ! SPACE_LOOKUP=$(echo "$SPACES_JSON" | jq -r '.resources | map({(.guid): {org_guid: .relationships.organization.data.guid, space_name: .name}}) | add' 2>/dev/null); then
    echo "Error: Failed to process spaces data" >&2
    exit 1
fi

# Validate that we have a valid timestamp
if [[ "$SIXTY_DAYS_AGO" == "0" || -z "$SIXTY_DAYS_AGO" ]]; then
    echo "Error: Failed to calculate date 60 days ago" >&2
    exit 1
fi

# Process apps and filter stopped apps older than 60 days
if ! echo "$APPS_JSON" | jq -r --argjson sixty_days_ago "$SIXTY_DAYS_AGO" \
   --argjson space_info "$SPACE_LOOKUP" \
   --argjson org_info "$ORG_LOOKUP" \
   '
   def iso_to_timestamp(date_str):
     date_str | strptime("%Y-%m-%dT%H:%M:%SZ") | mktime;
   
   .resources[] |
   select(.state == "STOPPED") |
   select(iso_to_timestamp(.updated_at) < $sixty_days_ago) |
   {
     app_name: .name,
     updated_at: .updated_at,
     created_at: .created_at,
     space_name: $space_info[.relationships.space.data.guid].space_name,
     space_id: .relationships.space.data.guid,
     org_name: $org_info[$space_info[.relationships.space.data.guid].org_guid],
     org_guid: $space_info[.relationships.space.data.guid].org_guid
   }
   ' > "$TEMP_RESULTS" 2>/dev/null; then
    echo "Error: Failed to process applications data" >&2
    echo "Debug info:"
    echo "- Sixty days ago timestamp: $SIXTY_DAYS_AGO"
    echo "- Space lookup sample: $(echo "$SPACE_LOOKUP" | head -c 100)..."
    echo "- Org lookup sample: $(echo "$ORG_LOOKUP" | head -c 100)..."
    exit 1
fi

# Count results
COUNT=$(jq -s length "$TEMP_RESULTS")

# Create CSV output
echo "app_name,updated_at,created_at,space_id,space_name,org_name,org_guid" > "$OUTPUT_FILE"

if [[ "$COUNT" -gt 0 ]]; then
    # Convert JSON to CSV
    jq -r '[.app_name, .updated_at, .created_at, .space_id, .space_name, .org_name, .org_guid] | @csv' "$TEMP_RESULTS" >> "$OUTPUT_FILE"
    
    echo "Found $COUNT stopped applications older than 60 days"
    echo "Results saved to: $OUTPUT_FILE"
    
    # Display first few results
    echo ""
    echo "First few results:"
    head -n 6 "$OUTPUT_FILE" | column -t -s ','
    
    if [[ "$COUNT" -gt 5 ]]; then
        echo "... and $((COUNT - 5)) more"
    fi
else
    echo "Found 0 stopped applications older than 60 days"
    echo "Empty CSV file created: $OUTPUT_FILE"
fi

# Additional statistics
echo ""
echo "Processing Summary:"

TOTAL_APPS=$(echo "$APPS_JSON" | jq '.resources | length')
STOPPED_APPS=$(echo "$APPS_JSON" | jq '.resources | map(select(.state == "STOPPED")) | length')

echo "- Total applications processed: $TOTAL_APPS"
echo "- Stopped applications found: $STOPPED_APPS"
echo "- Stopped applications older than 60 days: $COUNT"

# Show pagination info if available
PAGINATION_INFO=$(echo "$APPS_JSON" | jq -r '.pagination // empty')
if [[ -n "$PAGINATION_INFO" ]]; then
    TOTAL_RESULTS=$(echo "$APPS_JSON" | jq -r '.pagination.total_results')
    CURRENT_COUNT=$(echo "$APPS_JSON" | jq -r '.resources | length')
    
    echo "- Total results across all pages: $TOTAL_RESULTS"
    echo "- Current page shows: $CURRENT_COUNT of $TOTAL_RESULTS total apps"
    
    NEXT_PAGE=$(echo "$APPS_JSON" | jq -r '.pagination.next // empty')
    if [[ -n "$NEXT_PAGE" ]]; then
        echo "Warning: This appears to be a paginated response. You may need to fetch additional pages to get all applications."
    fi
fi

echo "Script completed successfully."
