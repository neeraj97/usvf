#!/bin/bash

###############################################################################
# ISO Repacking Module
# Repacks modified filesystem into new ISO image
###############################################################################

repack_iso() {
    local work_dir="$1"
    local output_file="$2"
    
    local iso_extract="${work_dir}/iso_extract"
    local squashfs_extract="${work_dir}/squashfs_extract"
    
    # Create new squashfs filesystem
    echo "  - Creating squashfs filesystem (this may take a while)..."
    rm -f "${iso_extract}/casper/filesystem.squashfs"
    
    mksquashfs "$squashfs_extract" \
        "${iso_extract}/casper/filesystem.squashfs" \
        -comp xz \
        -b 1M \
        -Xdict-size 100% \
        -noappend \
        -no-progress
    
    # Update filesystem size
    echo "  - Updating filesystem manifest..."
    printf $(du -sx --block-size=1 "$squashfs_extract" | cut -f1) > \
        "${iso_extract}/casper/filesystem.size"
    
    # Update MD5 sums
    echo "  - Calculating MD5 checksums..."
    cd "$iso_extract"
    
    # Remove old md5sum.txt
    rm -f md5sum.txt
    
    # Calculate new checksums
    find . -type f -not -name md5sum.txt -not -path "./isolinux/*" -print0 | \
        xargs -0 md5sum > md5sum.txt
    
    # Create new ISO
    echo "  - Creating bootable ISO image..."
    
    # Get volume ID from original ISO
    local volume_id="Ubuntu 24.04 Custom"
    
    xorriso -as mkisofs \
        -r -V "$volume_id" \
        -o "$output_file" \
        -J -l -b isolinux/isolinux.bin \
        -c isolinux/boot.cat \
        -no-emul-boot \
        -boot-load-size 4 \
        -boot-info-table \
        -eltorito-alt-boot \
        -e boot/grub/efi.img \
        -no-emul-boot \
        -isohybrid-gpt-basdat \
        -isohybrid-apm-hfsplus \
        -isohybrid-mbr /usr/lib/ISOLINUX/isohdpfx.bin \
        "$iso_extract" 2>&1 | grep -v "xorriso : UPDATE"
    
    cd - > /dev/null
    
    # Make ISO hybrid (bootable from USB)
    echo "  - Making ISO hybrid bootable..."
    if command -v isohybrid &> /dev/null; then
        isohybrid "$output_file" 2>/dev/null || true
    fi
    
    echo "  - ISO repacking completed"
    return 0
}
