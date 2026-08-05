#!/bin/sh
# writer.sh - write a string to a file, creating the path if needed.
#
# Usage: writer.sh <writefile> <writestr>
#   writefile: full path to the file to create (including the filename)
#   writestr:  text string to write into that file
#
# Overwrites writefile if it already exists. Exits 1 on any error.
# Author: v2h

set -u

# Require both arguments
if [ $# -lt 2 ]; then
    echo "Error: missing arguments." >&2
    echo "Usage: $0 <writefile> <writestr>" >&2
    exit 1
fi

writefile=$1
writestr=$2

# Create the containing directory path if it does not already exist
writedir=$(dirname "$writefile")
if ! mkdir -p "$writedir"; then
    echo "Error: could not create directory '$writedir'." >&2
    exit 1
fi

# Write the string, overwriting any existing content
if ! printf '%s\n' "$writestr" > "$writefile"; then
    echo "Error: could not create file '$writefile'." >&2
    exit 1
fi
