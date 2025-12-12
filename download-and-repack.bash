#!/usr/bin/env bash

# Vars
DEFAULT_ROOTFS_URL='https://mirrors.ustc.edu.cn/archlinuxarm/os/ArchLinuxARM-aarch64-latest.tar.gz'
DEFAULT_OUTPUT='rootfs.img'
DEFAULT_SIZE='auto'
AUTO_BUFFER_MB='500'

# Args
target_url="${1:-$DEFAULT_ROOTFS_URL}"
output_img="${2:-$DEFAULT_OUTPUT}"
target_size_mb="${3:-$DEFAULT_SIZE}"

# Grant root permission
if [[ $(id -u) -ne 0 ]]; then
    ./elevator $0 $@
    exit
fi

# Prepare work dir
work_dir="$(mktemp -d chroot-distro.XXXXXXXX --tmpdir)"

# Cleanup
cleanup() {
    echo 'Cleaning up'
    if mountpoint -q "$work_dir/mnt"; then
        umount "$work_dir/mnt"
    fi
    rm -r "$work_dir"
    echo 'Clean up finished'
}
trap cleanup EXIT

# Download file
downloaded_file="$work_dir/rootfs-tarball"
echo "Start downloading from \"$target_url\"..."
curl -# "$target_url" -o "$downloaded_file"
if [[ ! -f "$downloaded_file" ]]; then
    echo 'Download failed'
    exit 1
fi

# Extract file
extract_dir="$work_dir/rootfs-content"
mkdir -p "$extract_dir"
echo 'Extracting...'
tar --numeric-owner -xpf "$downloaded_file" -C "$extract_dir"

# Calculate image size
content_size_kb="$(du -s "$extract_dir" | cut -f1)"
content_size_mb="$((content_size_kb / 1024))"
min_safe_size=$((content_size_mb + AUTO_BUFFER_MB))
echo "Actual content size: $content_size_mb MB"
echo "Minimum safe size: $min_safe_size MB"
if [[ "$target_size_mb" == 'auto' ]]; then
    final_size="$min_safe_size"
    echo "Automatically set image size to $final_size MB"
else
    if ! [[ "$target_size_mb" =~ ^[0-9]+$ ]]; then
        echo 'Error: size must be a integral (MB)'
        exit 1
    fi
    if [[ "$target_size_mb" -lt "$min_safe_size" ]]; then
        echo "Warning: size $target_size_mb MB is smaller than minimum ($min_safe_size MB)"
        echo 'Using minimum size'
        final_size="$min_safe_size"
    else
        final_size=$target_size_mb
        echo "Image size set to $final_size"
    fi
fi

# Creste and format img
echo 'Creating img file'
dd if=/dev/zero of="$output_img" bs=1M count="$final_size"
echo 'Formating'
mkfs.ext4 "$output_img" > /dev/null

# Write data
mount_point="$work_dir/mnt"
mkdir -p "$mount_point"
echo 'Writing data to img'
mount -t ext4 -o loop,rw "$output_img" "$mount_point"
cp -a "$extract_dir/." "$mount_point/"

umount "$mount_point"
echo "Image create complete: "$output_img""
echo "Size: "$(du -hs "$output_img" | cut -f1)""
echo
