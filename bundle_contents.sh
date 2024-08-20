#!/bin/bash

# Define the output file
output_file="bundled_contents.txt"

# Define the directories relative to the current directory
directories=(
    "./src"
    # "./test"
    # "./script"
)

# Clear the output file if it already exists
> "$output_file"

# Loop through each directory
for dir in "${directories[@]}"; do
    # Check if the directory exists
    if [ -d "$dir" ]; then
        # Find all files in the directory and its subdirectories
        find "$dir" -type f | while read -r file; do
            # Write the file path to the output file
            echo "File: $file" >> "$output_file"
            echo "----------------------------------------" >> "$output_file"
            
            # Write the contents of the file to the output file
            cat "$file" >> "$output_file"
            
            # Add a separator between files
            echo -e "\n\n========================================\n\n" >> "$output_file"
        done
    else
        echo "Directory not found: $dir" >&2
    fi
done

echo "All contents have been bundled into $output_file"
