#!/usr/bin/env bash
# Dell XPS 15 9500 - Arch Linux ZFS Pre-Install Script
# https://github.com/danielbodnar/archconfigs/tree/main/scripts/dell-xps-init.sh
#
# Run from archiso before archinstall:
#   curl -fsSL https://raw.githubusercontent.com/danielbodnar/archconfigs/main/scripts/dell-xps-init.sh | bash
#
# Or download and run:
#   curl -fsSLO https://raw.githubusercontent.com/danielbodnar/archconfigs/main/scripts/dell-xps-init.sh
#   chmod +x dell-xps-init.sh
#   ./dell-xps-init.sh

set -euo pipefail

readonly POOL_NAME="${ZFS_POOL_NAME:-zroot}"
readonly DISK="${ZFS_DISK:-/dev/nvme0n1}"
readonly EFI_PART="${DISK}p1"
readonly ZFS_PART="${DISK}p2"
readonly GITHUB_USER="${GITHUB_SSH_USER:-danielbodnar}"

log() { printf '\033[1;34m[%s]\033[0m %s\n' "$(date '+%H:%M:%S')" "$*"; }
info() { log "INFO: $*"; }
warn() { printf '\033[1;33m[%s] WARN:\033[0m %s\n' "$(date '+%H:%M:%S')" "$*"; }
error() { printf '\033[1;31m[%s] ERROR:\033[0m %s\n' "$(date '+%H:%M:%S')" "$*"; exit 1; }

check_archiso() {
    [[ -f /run/archiso/bootmnt/arch/boot/x86_64/vmlinuz-linux ]] || \
        warn "Not running from archiso - proceed with caution"
}

check_uefi() {
    [[ -d /sys/firmware/efi/efivars ]] || error "UEFI mode required"
}

setup_zfs_archiso() {
    info "Setting up ZFS on archiso..."
    
    if ! command -v zpool &>/dev/null; then
        info "Installing ZFS modules via eoli3n/archiso-zfs..."
        curl -s https://raw.githubusercontent.com/eoli3n/archiso-zfs/master/init | bash
    else
        info "ZFS already available"
    fi
}

setup_archzfs_repo() {
    info "Configuring archzfs repository..."
    
    if ! grep -q '^\[archzfs\]' /etc/pacman.conf; then
        cat >> /etc/pacman.conf << 'EOF'

[archzfs]
Server = https://archzfs.com/$repo/$arch
SigLevel = Optional TrustAll
EOF
    fi
    
    # Import and sign key
    pacman-key --recv-keys DDF7DB817396A49B2A2723F7403BD972F75D9D76 2>/dev/null || true
    pacman-key --lsign-key DDF7DB817396A49B2A2723F7403BD972F75D9D76 2>/dev/null || true
    pacman -Sy --noconfirm
    
    info "archzfs repository configured"
}

partition_disk() {
    info "Partitioning $DISK..."
    
    # Wipe existing signatures
    wipefs -af "$DISK"
    
    # Create GPT partition table
    parted -s "$DISK" mklabel gpt
    
    # EFI partition (1GB)
    parted -s "$DISK" mkpart "EFI" fat32 1MiB 1GiB
    parted -s "$DISK" set 1 esp on
    
    # ZFS partition (rest of disk)
    parted -s "$DISK" mkpart "ZFS" 1GiB 100%
    
    # Format EFI partition
    mkfs.fat -F32 -n ESP "$EFI_PART"
    
    info "Partitioning complete"
    parted -s "$DISK" print
}

create_zfs_pool() {
    info "Creating ZFS pool '$POOL_NAME' on $ZFS_PART..."
    
    # Destroy existing pool if present
    zpool destroy "$POOL_NAME" 2>/dev/null || true
    
    # Create pool with optimal settings for NVMe SSD
    zpool create -f \
        -o ashift=12 \
        -o autotrim=on \
        -O acltype=posixacl \
        -O canmount=off \
        -O compression=zstd \
        -O dnodesize=auto \
        -O normalization=formD \
        -O relatime=on \
        -O xattr=sa \
        -O mountpoint=none \
        "$POOL_NAME" "$ZFS_PART"
    
    info "ZFS pool created"
}

create_zfs_datasets() {
    info "Creating ZFS datasets..."
    
    # ROOT container
    zfs create -o canmount=off -o mountpoint=none "$POOL_NAME/ROOT"
    
    # Main root dataset
    zfs create -o canmount=noauto -o mountpoint=/ "$POOL_NAME/ROOT/arch"
    
    # Home
    zfs create -o canmount=on -o mountpoint=/home "$POOL_NAME/home"
    
    # Var container
    zfs create -o canmount=off -o mountpoint=none "$POOL_NAME/var"
    
    # Var subdatasets
    zfs create -o canmount=on -o mountpoint=/var/log "$POOL_NAME/var/log"
    zfs create -o canmount=on -o mountpoint=/var/cache "$POOL_NAME/var/cache"
    zfs create -o canmount=on -o mountpoint=/var/cache/pacman/pkg "$POOL_NAME/var/cache/pacman/pkg"
    
    # Set bootfs
    zpool set bootfs="$POOL_NAME/ROOT/arch" "$POOL_NAME"
    
    info "ZFS datasets created:"
    zfs list -r "$POOL_NAME"
}

mount_filesystems() {
    info "Mounting filesystems at /mnt..."
    
    # Export and reimport with proper mount root
    zpool export "$POOL_NAME"
    zpool import -d /dev/disk/by-id -R /mnt "$POOL_NAME" -N
    
    # Mount root first
    zfs mount "$POOL_NAME/ROOT/arch"
    
    # Mount remaining datasets
    zfs mount -a
    
    # Create and mount EFI
    mkdir -p /mnt/boot
    mount "$EFI_PART" /mnt/boot
    
    info "Filesystems mounted:"
    findmnt -R /mnt
}

fetch_ssh_keys() {
    info "Fetching SSH keys from github.com/$GITHUB_USER..."
    
    local ssh_dir="/mnt/etc/skel/.ssh"
    mkdir -p "$ssh_dir"
    
    if curl -fsSL "https://github.com/${GITHUB_USER}.keys" > "$ssh_dir/authorized_keys" 2>/dev/null; then
        chmod 700 "$ssh_dir"
        chmod 600 "$ssh_dir/authorized_keys"
        info "SSH keys saved to /etc/skel/.ssh/authorized_keys (will be copied to new users)"
    else
        warn "Failed to fetch SSH keys from GitHub"
    fi
}

print_next_steps() {
    cat << EOF

┌──────────────────────────────────────────────────────────────────────────────┐
│                     ZFS Pre-Install Setup Complete!                          │
├──────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│  Pool: $POOL_NAME                                                            │
│  Disk: $DISK                                                                 │
│                                                                              │
│  Next steps:                                                                 │
│                                                                              │
│  1. Run archinstall with your ZFS config:                                    │
│     archinstall --config user_configuration_zfs.json                         │
│                                                                              │
│  2. Or continue manually:                                                    │
│     pacstrap -K /mnt base linux linux-zen linux-firmware                     │
│     pacstrap -K /mnt zfs-linux zfs-linux-zen zfs-utils                       │
│     genfstab -U /mnt >> /mnt/etc/fstab                                       │
│     arch-chroot /mnt                                                         │
│                                                                              │
│  3. After install, run the Hyprland setup script:                            │
│     curl -fsSL https://raw.githubusercontent.com/danielbodnar/archconfigs/   │
│       main/scripts/xps9500-hyprland-setup.sh | sudo bash                     │
│                                                                              │
│  Important ZFS services to enable:                                           │
│     systemctl enable zfs.target                                              │
│     systemctl enable zfs-import-cache.service                                │
│     systemctl enable zfs-mount.service                                       │
│                                                                              │
└──────────────────────────────────────────────────────────────────────────────┘

EOF
}

main() {
    info "Dell XPS 15 9500 - ZFS Pre-Install Script"
    info "Pool: $POOL_NAME | Disk: $DISK | GitHub: $GITHUB_USER"
    
    check_archiso
    check_uefi
    setup_zfs_archiso
    setup_archzfs_repo
    partition_disk
    create_zfs_pool
    create_zfs_datasets
    mount_filesystems
    fetch_ssh_keys
    print_next_steps
    
    info "Pre-install setup complete!"
}

# Allow sourcing without execution
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
