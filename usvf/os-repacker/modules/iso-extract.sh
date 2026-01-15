#!/bin/bash

###############################################################################
# ISO Extraction Module
# Extracts Ubuntu ISO image for modification
###############################################################################

extract_iso() {
    local iso_file="$1"
    local work_dir="$2"
    
    local iso_mount="${work_dir}/iso_mount"
    local iso_extract="${work_dir}/iso_extract"
    local squashfs_mount="${work_dir}/squashfs_mount"
    local squashfs_extract="${work_dir}/squashfs_extract"
    
    # Create directories
    mkdir -p "$iso_mount" "$iso_extract" "$squashfs_mount" "$squashfs_extract"
    
    # Mount ISO
    echo "  - Mounting ISO image..."
    mount -o loop "$iso_file" "$iso_mount"
    
    # Copy ISO contents
    echo "  - Copying ISO contents..."
    rsync -a --exclude=/casper/filesystem.squashfs "$iso_mount/" "$iso_extract/"
    
    # Extract squashfs filesystem
    echo "  - Extracting squashfs filesystem (this may take a while)..."
    if [[ -f "$iso_mount/casper/filesystem.squashfs" ]]; then
        unsquashfs -f -d "$squashfs_extract" "$iso_mount/casper/filesystem.squashfs"
    else
        umount "$iso_mount"
        echo "ERROR: filesystem.squashfs not found in ISO"
        return 1
    fi
    
    # Unmount ISO
    umount "$iso_mount"
    
    echo "  - ISO extraction completed"
    return 0
}
