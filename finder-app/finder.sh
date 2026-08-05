#!/bin/sh
# finder.sh - count files in a directory tree and lines matching a string.
#
# Usage: finder.sh <filesdir> <searchstr>
#   filesdir:  path to a directory to search (recursively)
#   searchstr: text string to search for within the files
#
# Prints: "The number of files are X and the number of matching lines are Y"
#   X = number of regular files under filesdir (including subdirectories)
#   Y = number of lines across those files that contain searchstr
# Exits 1 on any error.
# Author: v2h

set -u

# Require both arguments
if [ $# -lt 2 ]; then
    echo "Error: missing arguments." >&2
    echo "Usage: $0 <filesdir> <searchstr>" >&2
    exit 1
fi

filesdir=$1
searchstr=$2

# filesdir must be an existing directory
if [ ! -d "$filesdir" ]; then
    echo "Error: '$filesdir' is not a directory." >&2
    exit 1
fi

# X: number of regular files in the tree
numfiles=$(find "$filesdir" -type f | wc -l)

# Y: number of matching lines across those files
nummatching=$(grep -r "$searchstr" "$filesdir" | wc -l)

echo "The number of files are ${numfiles} and the number of matching lines are ${nummatching}"
