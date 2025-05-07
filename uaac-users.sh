#!/bin/bash


USERS=($(uaac users | grep "username:" | awk '{print $2}'))
# Extract all display values and store them in an array
GROUP_DISPLAYS=($(uaac user get smoke_tests | grep "display:" | sed 's/.*display: \(.*\)/\1/'))

# Function to extract description from uaac group get output
get_group_description() {
  group=$1
  # Run uaac group get and capture the output
  group_output=$(uaac group get "$group")

  # Extract the description line
  description=$(echo "$group_output" | grep "description:" | sed 's/.*description: \(.*\)/\1/')

  # Print the group name and description
  echo "Group: $group"
  echo "Description: $description"
  echo "----------------------------------------"
}

for user in "${USERS[@]}"; do
    echo "Processing $user..."
    group_displays=($(uaac user get $user | grep "display:" | sed 's/.*display: \(.*\)/\1/'))
    echo "Processing ${#group_displays[@]} groups..."
    for group in "${group_displays[@]}"; do
        get_group_description "$group"
    done
    echo "\n\n\n\n"
done
