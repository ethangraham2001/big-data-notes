#!/bin/bash

# Function to check if pandoc is installed
check_pandoc() {
    if ! command -v pandoc &> /dev/null; then
        echo "Error: pandoc is not installed. Please install it first."
        exit 1
    fi
}

# Function to check if required files exist
check_files() {
    local required_files=("metadata.md")
    for file in "${required_files[@]}"; do
        if [ ! -f "$file" ]; then
            echo "Error: Required file $file not found."
            exit 1
        fi
    done
}

# Function to get all numbered markdown files in correct order
get_numbered_files() {
    # Find all files matching the pattern ##-*.md, sort them naturally
    find . -maxdepth 1 -type f -name "[0-9][0-9]-*.md" | sort -n
}

# Function to build the PDF
build_pdf() {
    local output_file="notes.pdf"
    local numbered_files=$(get_numbered_files)
    
    # Start with metadata.md and then add all numbered files
    local files_to_process="metadata.md $numbered_files"
    
    echo "Processing files in the following order:"
    echo "$files_to_process" | tr ' ' '\n'
    echo "------------------------"
    
    # Convert to PDF using pandoc
    pandoc $files_to_process \
        --pdf-engine=xelatex \
        -o "$output_file" \
        --toc \
        --toc-depth=3 \
        --number-sections \
        2>&1 || {
            echo "Error: PDF generation failed"
            exit 1
        }
    
    if [ -f "$output_file" ]; then
        echo "Successfully generated $output_file"
    else
        echo "Error: Failed to generate PDF"
        exit 1
    fi
}

main() {
    # Change to the script's directory
    cd "$(dirname "$0")" || exit 1
    
    # Run checks
    check_pandoc
    check_files
    
    # Build the PDF
    build_pdf
}

# Run main function
main
