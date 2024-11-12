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



# Function to check if a package dependency is satisfied using pkg-config
check_dependencies() {
    # Ensure the user provided a package name
    if [ -z "$1" ]; then
        echo "ERROR: You must specify a package name to check dependencies."
        return 1
    fi

    pkgname="$1"
    
    # Fetch the PKGBUILD from GitHub repository
    pkgbuild_url="${REPO_URL}/raw/main/$pkgname/PKGBUILD"
    pkgbuild=$(curl -s "$pkgbuild_url")

    # Check if the PKGBUILD file exists in the repository
    if [ -z "$pkgbuild" ]; then
        echo "ERROR: Package $pkgname not found in repository."
        return 1
    fi

    # Extract dependencies from PKGBUILD
    dependencies=$(echo "$pkgbuild" | grep -oP 'dependencies=\([^\)]*\)' | sed -e 's/dependencies=//g' -e 's/\[\]//g' -e 's/[\'"']//g')

    # Split dependencies into an array
    IFS=' ' read -r -a deps <<< "$dependencies"

    # Loop over each dependency
    for dep in "${deps[@]}"; do
        if [ -z "$dep" ]; then
            continue
        fi

        # Use pkg-config to check if the dependency is installed
        if pkg-config --exists "$dep"; then
            echo "Dependency $dep is already installed on the system."
        else
            echo "ERROR: Dependency $dep is not satisfied!"
            return 1
        fi
    done

    # If all dependencies are satisfied
    echo "All dependencies for $pkgname are satisfied."
    return 0
}


cracken_prepare() {
    # Ensure the user provided a package name
    if [ -z "$1" ]; then
        echo "ERROR: You must specify a package name."
        return 1
    fi

    pkgname="$1"
    
    # Define the directory to extract the tarball
    BUILD_DIR="/tmp/build"

    # Check if the source directory exists
    if [ ! -d "$SOURCE_DIR" ]; then
        echo "ERROR: Source directory $SOURCE_DIR does not exist. Run 'get_package' first."
        return 1
    fi

    # Fetch the PKGBUILD from the GitHub repository
    pkgbuild_url="${REPO_URL}/raw/main/$pkgname/PKGBUILD"
    pkgbuild=$(curl -s "$pkgbuild_url")

    # Check if the PKGBUILD file exists in the repository
    if [ -z "$pkgbuild" ]; then
        echo "ERROR: Package $pkgname not found in repository."
        return 1
    fi

    # Extract the source URL from the PKGBUILD
    source_url=$(echo "$pkgbuild" | grep -oP 'sources=\([^\)]*\)' | sed -e 's/sources=//g' -e 's/[\'"']//g' | sed -e 's/\s*"\(.*\)"/\1/')
    tarball_name=$(basename "$source_url")

    # Check if the tarball exists in the source directory
    if [ ! -f "$SOURCE_DIR/$tarball_name" ]; then
        echo "ERROR: Tarball $tarball_name does not exist in $SOURCE_DIR. Run 'get_package' first."
        return 1
    fi

    # Create the build directory if it doesn't exist
    if [ ! -d "$BUILD_DIR" ]; then
        echo "Creating build directory $BUILD_DIR"
        mkdir -p "$BUILD_DIR"
    fi

    # Extract the tarball into the build directory
    echo "Extracting tarball $tarball_name into $BUILD_DIR..."
    tar -xf "$SOURCE_DIR/$tarball_name" -C "$BUILD_DIR"

    # Navigate to the extracted source directory
    extracted_dir="$BUILD_DIR/${pkgname}-$(echo "$tarball_name" | sed -e 's/.tar.xz//')"
    if [ ! -d "$extracted_dir" ]; then
        echo "ERROR: Extracted directory $extracted_dir does not exist."
        return 1
    fi
    cd "$extracted_dir" || return 1

    # Extract and run the cracken_prepare() function from the PKGBUILD
    prepare_cmds=$(echo "$pkgbuild" | grep -oP 'cracken_prepare\(\)\s*{[^}]*}' | sed 's/cracken_prepare() {//g' | sed 's/}//g' | tr '\n' ' ')

    # Check if cracken_prepare function exists
    if [ -z "$prepare_cmds" ]; then
        echo "ERROR: No cracken_prepare function found in PKGBUILD."
        return 1
    fi

    # Run the cracken_prepare commands
    echo "Running preparation commands from cracken_prepare..."
    eval "$prepare_cmds"

    # If everything worked fine
    echo "Package $pkgname is prepared and ready for building."
    return 0
}


cracken_build() {
    # Ensure the user provided a package name
    if [ -z "$1" ]; then
        echo "ERROR: You must specify a package name."
        return 1
    fi

    # Package name passed by user
    pkgname="$1"
    
    # Define the path to the PKGBUILD
    pkgbuild_url="${REPO_URL}/raw/main/$pkgname/PKGBUILD"
    
    # Fetch the PKGBUILD from the GitHub repository
    echo "Fetching PKGBUILD for $pkgname from GitHub..."
    pkgbuild=$(curl -s "$pkgbuild_url")

    # Check if the PKGBUILD file exists in the repository
    if [ -z "$pkgbuild" ]; then
        echo "ERROR: Package $pkgname not found in repository."
        return 1
    fi
    
    # Extract the cracken_build function from the PKGBUILD
    build_cmds=$(echo "$pkgbuild" | sed -n '/^cracken_build\(\)/,/^}/p' | sed '1d;$d')
    
    # Check if we successfully extracted the cracken_build function
    if [ -z "$build_cmds" ]; then
        echo "ERROR: cracken_build function not found in PKGBUILD."
        return 1
    fi
    
    # Ensure the build directory exists
    build_dir="$SOURCE_DIR/$pkgname-build"
    if [ ! -d "$build_dir" ]; then
        echo "ERROR: Build directory does not exist: $build_dir"
        return 1
    fi
    
    # Change to the build directory
    cd "$build_dir"
    
    # Execute the commands in cracken_build function
    echo "Executing build commands for $pkgname..."
    eval "$build_cmds"
    
    if [ $? -ne 0 ]; then
        echo "ERROR: Build process failed for $pkgname."
        return 1
    fi
    
    echo "$pkgname has been successfully built."
}

cracken_install() {
    # Ensure the user provided a package name
    if [ -z "$1" ]; then
        echo "ERROR: You must specify a package name."
        return 1
    fi

    # Package name passed by user
    pkgname="$1"
    
    # Define the path to the PKGBUILD
    pkgbuild_url="${REPO_URL}/raw/main/$pkgname/PKGBUILD"
    
    # Fetch the PKGBUILD from the GitHub repository
    echo "Fetching PKGBUILD for $pkgname from GitHub..."
    pkgbuild=$(curl -s "$pkgbuild_url")

    # Check if the PKGBUILD file exists in the repository
    if [ -z "$pkgbuild" ]; then
        echo "ERROR: Package $pkgname not found in repository."
        return 1
    fi
    
    # Extract the cracken_install function from the PKGBUILD
    install_cmds=$(echo "$pkgbuild" | sed -n '/^cracken_install\(\)/,/^}/p' | sed '1d;$d')
    
    # Check if we successfully extracted the cracken_install function
    if [ -z "$install_cmds" ]; then
        echo "ERROR: cracken_install function not found in PKGBUILD."
        return 1
    fi
    
    # Ensure the build directory exists
    build_dir="$SOURCE_DIR/$pkgname-build"
    if [ ! -d "$build_dir" ]; then
        echo "ERROR: Build directory does not exist: $build_dir"
        return 1
    fi

    # Define the manifest file path
    manifest_file="/var/lib/cracken/${pkgname}-${pkgver}-manifest.txt"
    mkdir -p "$(dirname "$manifest_file")"
    
    # Change to the build directory
    cd "$build_dir"

    # Take a snapshot of the system before installation
    find /usr /bin /lib /sbin /etc -type f > "/tmp/before_install.txt"

    # Execute the commands in cracken_install function
    echo "Executing install commands for $pkgname..."
    eval "$install_cmds"

    if [ $? -ne 0 ]; then
        echo "ERROR: Installation process failed for $pkgname."
        return 1
    fi

    # Take a snapshot of the system after installation
    find /usr /bin /lib /sbin /etc -type f > "/tmp/after_install.txt"

    # Generate the manifest file by finding new files
    comm -13 /tmp/before_install.txt /tmp/after_install.txt > "$manifest_file"
    
    # Cleanup temporary files
    rm /tmp/before_install.txt /tmp/after_install.txt

    echo "$pkgname has been successfully installed. Manifest file created at $manifest_file."
}



cracken_preinstall() {
    # Ensure the user provided a package name
    if [ -z "$1" ]; then
        echo "ERROR: You must specify a package name."
        return 1
    fi

    # Package name passed by user
    pkgname="$1"
    
    # Define the path to the PKGBUILD
    pkgbuild_url="${REPO_URL}/raw/main/$pkgname/PKGBUILD"
    
    # Fetch the PKGBUILD from the GitHub repository
    echo "Fetching PKGBUILD for $pkgname from GitHub..."
    pkgbuild=$(curl -s "$pkgbuild_url")

    # Check if the PKGBUILD file exists in the repository
    if [ -z "$pkgbuild" ]; then
        echo "ERROR: Package $pkgname not found in repository."
        return 1
    fi
    
    # Extract the cracken_preinstall function from the PKGBUILD
    preinstall_cmds=$(echo "$pkgbuild" | sed -n '/^cracken_preinstall\(\)/,/^}/p' | sed '1d;$d')
    
    # Check if we successfully extracted the cracken_preinstall function
    if [ -z "$preinstall_cmds" ]; then
        echo "ERROR: cracken_preinstall function not found in PKGBUILD."
        return 1
    fi
    
    # Change to the package's build directory (optional step if needed)
    build_dir="$SOURCE_DIR/$pkgname-build"
    if [ ! -d "$build_dir" ]; then
        echo "ERROR: Build directory does not exist: $build_dir"
        return 1
    fi
    cd "$build_dir"

  
cracken_postinstall() {
    # Ensure the user provided a package name
    if [ -z "$1" ]; then
        echo "ERROR: You must specify a package name."
        return 1
    fi

    # Package name passed by user
    pkgname="$1"
    
    # Define the path to the PKGBUILD
    pkgbuild_url="${REPO_URL}/raw/main/$pkgname/PKGBUILD"
    
    # Fetch the PKGBUILD from the GitHub repository
    echo "Fetching PKGBUILD for $pkgname from GitHub..."
    pkgbuild=$(curl -s "$pkgbuild_url")

    # Check if the PKGBUILD file exists in the repository
    if [ -z "$pkgbuild" ]; then
        echo "ERROR: Package $pkgname not found in repository."
        return 1
    fi
    
    # Extract the cracken_postinstall function from the PKGBUILD
    postinstall_cmds=$(echo "$pkgbuild" | sed -n '/^cracken_postinstall\(\)/,/^}/p' | sed '1d;$d')
    
    # Check if we successfully extracted the cracken_postinstall function
    if [ -z "$postinstall_cmds" ]; then
        echo "ERROR: cracken_postinstall function not found in PKGBUILD."
        return 1
    fi

    # Change to the package's build directory (optional if needed)
    build_dir="$SOURCE_DIR/$pkgname-build"
    if [ ! -d "$build_dir" ]; then
        echo "ERROR: Build directory does not exist: $build_dir"
        return 1
    fi
    cd "$build_dir"

    # Execute the commands in cracken_postinstall function
    echo "Executing post-install commands for $pkgname..."
    eval "$postinstall_cmds"
    
    if [ $? -ne 0 ]; then
        echo "ERROR: Post-installation process


cracken_uninstall() {
    # Ensure the user provided a package name
    if [ -z "$1" ]; then
        echo "ERROR: You must specify a package name to uninstall."
        return 1
    fi

    # Package name passed by user
    pkgname="$1"

    # Define the path to the manifest file
    manifest_file="/var/lib/cracken/${pkgname}-manifest.txt"

    # Check if the manifest file exists
    if [ ! -f "$manifest_file" ]; then
        echo "ERROR: Manifest file for $pkgname not found. The package may not be installed."
        return 1
    fi

    echo "Uninstalling $pkgname..."

    # Read each line in the manifest file and delete the file
    while IFS= read -r file; do
        if [ -f "$file" ] || [ -d "$file" ]; then
            rm -rf "$file"
            echo "Removed $file"
        else
            echo "WARNING: File $file not found, skipping."
        fi
    done < "$manifest_file"

    # Remove the manifest file after uninstall
    rm -f "$manifest_file"
    echo "$pkgname has been successfully uninstalled."
}
