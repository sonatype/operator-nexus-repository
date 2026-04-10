#!/usr/bin/env bash
#
# Copy operator metadata from operator-nexus-repository to certified-operators
#
# Usage: ./copy-to-certified.sh <operator-version>
# Example: ./copy-to-certified.sh 3.90.3-1

set -e  # Exit on error

if [ -z "$1" ]; then
  echo "Usage: $0 <operator-version>"
  echo "Example: $0 3.90.3-1"
  exit 1
fi

VERSION="$1"

# Define paths
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
SOURCE_DIR="$PROJECT_ROOT/deploy/olm-catalog/nexus-repository-ha-operator-certified/$VERSION"
DEST_DIR="$(cd "$PROJECT_ROOT/.." && pwd)/certified-operators/operators/nexus-repository-ha-operator-certified/$VERSION"

# Validate source directory exists
if [ ! -d "$SOURCE_DIR" ]; then
  echo "Error: Source directory does not exist: $SOURCE_DIR"
  exit 1
fi

# Check if manifests and metadata directories exist in source
if [ ! -d "$SOURCE_DIR/manifests" ] || [ ! -d "$SOURCE_DIR/metadata" ]; then
  echo "Error: Source directory missing manifests or metadata subdirectories"
  exit 1
fi

echo "Copying operator version $VERSION..."
echo "  From: $SOURCE_DIR"
echo "  To:   $DEST_DIR"

# Create destination directory if it doesn't exist
mkdir -p "$DEST_DIR"

# Copy manifests and metadata directories
cp -r "$SOURCE_DIR/manifests" "$DEST_DIR/"
cp -r "$SOURCE_DIR/metadata" "$DEST_DIR/"

echo "✓ Successfully copied metadata files for version $VERSION"
echo ""
echo "Files copied:"
ls -la "$DEST_DIR"