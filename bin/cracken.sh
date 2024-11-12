#!/bin/bash

# Define the source directory
SOURCE_DIR="/sources"
REPO_URL="https://github.com/n1cef/cracken_repo"

# Function to download the package
get_package() {
    # Ensure the user provided a package name
    if [ -z "$1" ]; then
        echo "ERROR: You must specify a package name."
        return 1
    fi

    # Package name passed by user
    pkgname="$1"

    # Check if the source directory exists, create if it doesn't
    if [ ! -d "$SOURCE_DIR" ]; then
        echo "Creating source directory $SOURCE_DIR"
        mkdir -p "$SOURCE_DIR"
    fi

    # Search the repository for the PKGBUILD file corresponding to the package
    pkgbuild_url="${REPO_URL}/raw/main/$pkgname/PKGBUILD"

    # Fetch the PKGBUILD from the GitHub repository
    echo "Fetching PKGBUILD for $pkgname from GitHub..."
    pkgbuild=$(curl -s "$pkgbuild_url")

    # Check if the PKGBUILD file exists in the repository
    if [ -z "$pkgbuild" ]; then
        echo "ERROR: Package $pkgname not found in repository."
        return 1
    fi

    # Extract the source URL and checksum from the PKGBUILD (simplified extraction)
    source_url=$(echo "$pkgbuild" | grep -oP 'sources=\([^\)]*\)' | sed -e 's/sources=//g' -e 's/[\'"']//g' | sed -e 's/\s*"\(.*\)"/\1/')
    checksum=$(echo "$pkgbuild" | grep -oP 'sha256sum=\([^\)]*\)' | sed -e 's/sha256sum=//g' -e 's/[\'"']//g' | sed -e 's/\s*"\(.*\)"/\1/')

    # Check if the source URL and checksum were extracted
    if [ -z "$source_url" ] || [ -z "$checksum" ]; then
        echo "ERROR: Failed to extract source URL or checksum from PKGBUILD."
        return 1
    fi

    # Download the source tarball
    echo "Downloading source tarball from $source_url..."
    wget -q "$source_url" -P "$SOURCE_DIR"

    # Get the downloaded tarball filename
    tarball_name=$(basename "$source_url")

    # Verify the checksum of the downloaded file
    echo "Verifying checksum for $tarball_name..."
    downloaded_checksum=$(sha256sum "$SOURCE_DIR/$tarball_name" | awk '{print $1}')

    if [ "$downloaded_checksum" != "$checksum" ]; then
        echo "ERROR: Checksum verification failed for $tarball_name."
        return 1
    else
        echo "Checksum verification successful."
    fi

    # Successfully downloaded and verified the package
    echo "$pkgname package has been downloaded and verified."
}
