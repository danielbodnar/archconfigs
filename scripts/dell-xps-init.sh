#!/usr/bin/env bash
# Dell XPS 15 9500 - Arch Linux ZFS Pre-Install Script
# https://github.com/danielbodnar/archconfigs/tree/main/scripts/dell-xps-init.sh
#
# Following OpenZFS Arch Linux Root on ZFS guide:
# https://openzfs.github.io/openzfs-docs/Getting%20Started/Arch%20Linux/Root%20on%20ZFS.html
#
# Run from archiso before archinstall:
#   curl -fsSL https://raw.githubusercontent.com/danielbodnar/archconfigs/main/scripts/dell-xps-init.sh | bash
#
# Or download and run:
#   curl -fsSLO https://raw.githubusercontent.com/danielbodnar/archconfigs/main/scripts/dell-xps-init.sh
#   chmod +x dell-xps-init.sh
#   ./dell-xps-init.sh
#
# Environment variables (optional - will prompt if not set):
#   ZFS_POOL_NAME  - Name for ZFS pool (default: zroot)
#   ZFS_DISK       - Disk device to use (e.g., /dev/nvme0n1 or /dev/disk/by-id/...)
#   SWAP_SIZE      - Swap partition size in GB (default: 0 = no swap)
#   GITHUB_SSH_USER - GitHub username for SSH keys (default: danielbodnar)

set -euo pipefail

# Defaults
DEFAULT_POOL_NAME="zroot"
DEFAULT_SWAP_SIZE=0
DEFAULT_GITHUB_USER="danielbodnar"

# Colors
RED='\033[1;31m'
GREEN='\033[1;32m'
YELLOW='\033[1;33m'
BLUE='\033[1;34m'
NC='\033[0m' # No Color

log() { printf "${BLUE}[%s]${NC} %s\n" "$(date '+%H:%M:%S')" "$*"; }
info() { log "INFO: $*"; }
warn() { printf "${YELLOW}[%s] WARN:${NC} %s\n" "$(date '+%H:%M:%S')" "$*"; }
error() { printf "${RED}[%s] ERROR:${NC} %s\n" "$(date '+%H:%M:%S')" "$*"; exit 1; }
success() { printf "${GREEN}[%s] SUCCESS:${NC} %s\n" "$(date '+%H:%M:%S')" "$*"; }

# Get disk by-id path from device path
get_disk_by_id() {
    local device="$1"
    local by_id

    # If already a by-id path, return as-is
    if [[ "$device" == /dev/disk/by-id/* ]]; then
        echo "$device"
        return
    fi

    # Get the real device path
    local real_device
    real_device=$(readlink -f "$device")
    local device_name
    device_name=$(basename "$real_device")

    # Find by-id symlink
    by_id=$(find /dev/disk/by-id -type l -exec sh -c 'readlink -f "$1" | grep -q "'"$device_name"'$" && echo "$1"' _ {} \; 2>/dev/null | grep -v -E '(wwn|eui|lun)' | head -1 || true)

    if [[ -n "$by_id" ]]; then
        echo "$by_id"
    else
        warn "Could not find by-id path for $device, using device path"
        echo "$device"
    fi
}

# List available disks
list_disks() {
    info "Available disks:"
    echo ""
    lsblk -d -o NAME,SIZE,MODEL,TRAN -e 7,11 | head -1
    echo "─────────────────────────────────────────────────────────────"
    lsblk -d -o NAME,SIZE,MODEL,TRAN -e 7,11 | tail -n +2
    echo ""
    info "Disks by-id:"
    ls -la /dev/disk/by-id/ 2>/dev/null | grep -v -E '(part|wwn|eui|lun)' | grep -E '^l' | awk '{print "  " $NF " -> " $9}' | head -20
    echo ""
}

# Interactive device selection
prompt_for_disk() {
    if [[ -n "${ZFS_DISK:-}" ]]; then
        DISK="$ZFS_DISK"
        return
    fi

    list_disks

    echo ""
    printf "${YELLOW}Enter the disk to use for ZFS installation${NC}\n"
    printf "Examples: /dev/nvme0n1, /dev/sda, /dev/disk/by-id/nvme-Samsung_SSD...\n"
    printf "${YELLOW}WARNING: All data on this disk will be DESTROYED!${NC}\n"
    echo ""

    while true; do
        read -rp "Disk device: " DISK

        if [[ -z "$DISK" ]]; then
            warn "No disk specified. Please enter a disk device."
            continue
        fi

        # Resolve symlinks
        if [[ ! -e "$DISK" ]]; then
            warn "Device '$DISK' does not exist. Please try again."
            continue
        fi

        local real_disk
        real_disk=$(readlink -f "$DISK")

        # Check it's a block device
        if [[ ! -b "$real_disk" ]]; then
            warn "'$DISK' is not a block device. Please try again."
            continue
        fi

        # Confirm selection
        local disk_info
        disk_info=$(lsblk -d -o SIZE,MODEL "$real_disk" 2>/dev/null | tail -1 || echo "unknown")
        echo ""
        printf "${RED}You selected: $DISK${NC}\n"
        printf "Device: $real_disk\n"
        printf "Info: $disk_info\n"
        echo ""
        read -rp "Is this correct? ALL DATA WILL BE DESTROYED! [y/N]: " confirm
        if [[ "${confirm,,}" == "y" ]]; then
            break
        fi
    done
}

# Interactive pool name selection
prompt_for_pool_name() {
    if [[ -n "${ZFS_POOL_NAME:-}" ]]; then
        POOL_NAME="$ZFS_POOL_NAME"
        return
    fi

    echo ""
    printf "${YELLOW}Enter the ZFS pool name${NC}\n"
    printf "Default: $DEFAULT_POOL_NAME\n"
    echo ""
    read -rp "Pool name [$DEFAULT_POOL_NAME]: " POOL_NAME
    POOL_NAME="${POOL_NAME:-$DEFAULT_POOL_NAME}"

    # Validate pool name (alphanumeric, underscore, hyphen)
    if [[ ! "$POOL_NAME" =~ ^[a-zA-Z][a-zA-Z0-9_-]*$ ]]; then
        error "Invalid pool name '$POOL_NAME'. Must start with a letter and contain only letters, numbers, underscores, and hyphens."
    fi

    info "Using pool name: $POOL_NAME"
}

# Interactive swap size selection
prompt_for_swap_size() {
    if [[ -n "${SWAP_SIZE:-}" ]]; then
        return
    fi

    echo ""
    printf "${YELLOW}Enter swap partition size in GB (0 for no swap)${NC}\n"
    printf "Recommended: Equal to RAM for hibernation, or 0 for no swap\n"
    printf "Default: $DEFAULT_SWAP_SIZE (no swap)\n"
    echo ""
    read -rp "Swap size in GB [$DEFAULT_SWAP_SIZE]: " SWAP_SIZE
    SWAP_SIZE="${SWAP_SIZE:-$DEFAULT_SWAP_SIZE}"

    if [[ ! "$SWAP_SIZE" =~ ^[0-9]+$ ]]; then
        error "Invalid swap size '$SWAP_SIZE'. Must be a number."
    fi

    if [[ "$SWAP_SIZE" -gt 0 ]]; then
        info "Will create ${SWAP_SIZE}GB swap partition"
    else
        info "No swap partition will be created"
    fi
}

# Prompt for GitHub user
prompt_for_github_user() {
    GITHUB_USER="${GITHUB_SSH_USER:-$DEFAULT_GITHUB_USER}"
    echo ""
    printf "${YELLOW}Enter GitHub username for SSH keys${NC}\n"
    printf "Default: $GITHUB_USER\n"
    echo ""
    read -rp "GitHub username [$GITHUB_USER]: " input_user
    GITHUB_USER="${input_user:-$GITHUB_USER}"
}

check_archiso() {
    [[ -f /run/archiso/bootmnt/arch/boot/x86_64/vmlinuz-linux ]] || \
        warn "Not running from archiso - proceed with caution"
}

check_uefi() {
    [[ -d /sys/firmware/efi/efivars ]] || error "UEFI mode required. Boot in UEFI mode."
}

setup_zfs_archiso() {
    info "Setting up ZFS on archiso..."

    if ! command -v zpool &>/dev/null; then
        info "Installing ZFS modules via eoli3n/archiso-zfs..."
        curl -s https://raw.githubusercontent.com/eoli3n/archiso-zfs/master/init | bash
    else
        info "ZFS already available"
    fi

    # Verify ZFS is working
    if ! modprobe zfs 2>/dev/null; then
        error "Failed to load ZFS kernel module"
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
    local disk="$1"
    local swap_size="$2"

    info "Partitioning $disk..."

    # Get the real device path for partitioning
    local real_disk
    real_disk=$(readlink -f "$disk")

    # Wipe existing signatures
    wipefs -af "$real_disk"
    blkdiscard -f "$real_disk" 2>/dev/null || true

    # Calculate partition layout
    # EFI: 1GB, ZFS: rest (minus swap if specified)
    # Reserve 1GB at end for overprovisioning

    local reserve=1

    if [[ "$swap_size" -gt 0 ]]; then
        info "Creating partitions: EFI (1GB), ZFS (main), Swap (${swap_size}GB)"
        parted --script --align=optimal "$real_disk" -- \
            mklabel gpt \
            mkpart EFI fat32 1MiB 1GiB \
            mkpart ZFS 1GiB -$((swap_size + reserve))GiB \
            mkpart swap linux-swap -$((swap_size + reserve))GiB -${reserve}GiB \
            set 1 esp on
    else
        info "Creating partitions: EFI (1GB), ZFS (rest)"
        parted --script --align=optimal "$real_disk" -- \
            mklabel gpt \
            mkpart EFI fat32 1MiB 1GiB \
            mkpart ZFS 1GiB -${reserve}GiB \
            set 1 esp on
    fi

    # Wait for kernel to recognize partitions
    partprobe "$real_disk"
    sleep 2

    # Determine partition naming scheme
    if [[ "$real_disk" == *nvme* ]] || [[ "$real_disk" == *mmcblk* ]]; then
        EFI_PART="${real_disk}p1"
        ZFS_PART="${real_disk}p2"
        [[ "$swap_size" -gt 0 ]] && SWAP_PART="${real_disk}p3"
    else
        EFI_PART="${real_disk}1"
        ZFS_PART="${real_disk}2"
        [[ "$swap_size" -gt 0 ]] && SWAP_PART="${real_disk}3"
    fi

    # Format EFI partition
    mkfs.fat -F32 -n ESP "$EFI_PART"

    # Format swap if configured
    if [[ "$swap_size" -gt 0 ]] && [[ -n "${SWAP_PART:-}" ]]; then
        mkswap -L swap "$SWAP_PART"
        info "Swap partition created: $SWAP_PART"
    fi

    # Get by-id path for ZFS partition (recommended by OpenZFS)
    ZFS_PART_BYID=$(get_disk_by_id "$ZFS_PART")
    if [[ "$ZFS_PART_BYID" == /dev/disk/by-id/* ]]; then
        ZFS_PART_BYID="${ZFS_PART_BYID}-part2"
    else
        # Fallback: find the partition by-id path
        ZFS_PART_BYID=$(find /dev/disk/by-id -type l -exec sh -c 'readlink -f "$1" | grep -q "'"$(basename "$ZFS_PART")"'$" && echo "$1"' _ {} \; 2>/dev/null | grep -v -E '(wwn|eui|lun)' | head -1 || echo "$ZFS_PART")
    fi

    info "Partitioning complete"
    lsblk "$real_disk"
    info "ZFS partition (by-id): $ZFS_PART_BYID"
}

create_zfs_pool() {
    local pool_name="$1"
    local zfs_part="$2"

    info "Creating ZFS pool '$pool_name' on $zfs_part..."

    # Destroy existing pool if present
    zpool destroy "$pool_name" 2>/dev/null || true

    # Create pool with optimal settings following OpenZFS recommendations
    # Reference: https://openzfs.github.io/openzfs-docs/Getting%20Started/Arch%20Linux/Root%20on%20ZFS.html
    zpool create -f \
        -o ashift=12 \
        -o autotrim=on \
        -R /mnt \
        -O acltype=posixacl \
        -O canmount=off \
        -O compression=zstd \
        -O dnodesize=auto \
        -O normalization=formD \
        -O relatime=on \
        -O xattr=sa \
        -O mountpoint=none \
        "$pool_name" "$zfs_part"

    success "ZFS pool '$pool_name' created"
}

create_zfs_datasets() {
    local pool_name="$1"

    info "Creating ZFS datasets..."

    # Root dataset with legacy mount (recommended for boot)
    zfs create -o canmount=noauto -o mountpoint=legacy "$pool_name/root"

    # Home dataset
    zfs create -o mountpoint=legacy "$pool_name/home"

    # Var container
    zfs create -o canmount=off -o mountpoint=none "$pool_name/var"

    # Var subdatasets
    zfs create -o mountpoint=legacy "$pool_name/var/log"
    zfs create -o mountpoint=legacy "$pool_name/var/cache"

    # Optional: separate dataset for pacman cache
    zfs create -o mountpoint=legacy -o com.sun:auto-snapshot=false "$pool_name/var/cache/pacman"

    # Optional: docker/podman storage (if using containers)
    zfs create -o mountpoint=legacy -o com.sun:auto-snapshot=false "$pool_name/var/lib"

    # Set bootfs property
    zpool set bootfs="$pool_name/root" "$pool_name"

    success "ZFS datasets created"
    zfs list -r "$pool_name"
}

mount_filesystems() {
    local pool_name="$1"

    info "Mounting filesystems at /mnt..."

    # Mount root first
    mount -t zfs "$pool_name/root" /mnt

    # Create mount points
    mkdir -p /mnt/{home,var/log,var/cache/pacman,var/lib,boot}

    # Mount other datasets
    mount -t zfs "$pool_name/home" /mnt/home
    mount -t zfs "$pool_name/var/log" /mnt/var/log
    mount -t zfs "$pool_name/var/cache" /mnt/var/cache
    mount -t zfs "$pool_name/var/cache/pacman" /mnt/var/cache/pacman
    mount -t zfs "$pool_name/var/lib" /mnt/var/lib

    # Mount EFI
    mount "$EFI_PART" /mnt/boot

    # Enable swap if configured
    if [[ -n "${SWAP_PART:-}" ]]; then
        swapon "$SWAP_PART"
        info "Swap enabled: $SWAP_PART"
    fi

    success "Filesystems mounted"
    findmnt -R /mnt
}

generate_hostid() {
    info "Generating ZFS hostid..."

    # Generate hostid for ZFS (required for pool import)
    # This will be copied to the installed system
    zgenhostid -f -o /mnt/etc/hostid 2>/dev/null || zgenhostid -f

    # Copy to target if not already there
    if [[ ! -f /mnt/etc/hostid ]]; then
        mkdir -p /mnt/etc
        cp /etc/hostid /mnt/etc/hostid
    fi

    success "Hostid generated: $(cat /etc/hostid | xxd -p)"
}

fetch_ssh_keys() {
    local github_user="$1"
    info "Fetching SSH keys from github.com/$github_user..."

    local ssh_dir="/mnt/etc/skel/.ssh"
    mkdir -p "$ssh_dir"

    if curl -fsSL "https://github.com/${github_user}.keys" > "$ssh_dir/authorized_keys" 2>/dev/null; then
        chmod 700 "$ssh_dir"
        chmod 600 "$ssh_dir/authorized_keys"
        success "SSH keys saved to /etc/skel/.ssh/authorized_keys"
    else
        warn "Failed to fetch SSH keys from GitHub"
    fi
}

create_zfs_cache() {
    info "Creating ZFS cache file..."

    mkdir -p /mnt/etc/zfs
    zpool set cachefile=/etc/zfs/zpool.cache "$POOL_NAME"
    cp /etc/zfs/zpool.cache /mnt/etc/zfs/

    success "ZFS cache file created"
}

print_mkinitcpio_instructions() {
    cat << 'EOF'

┌──────────────────────────────────────────────────────────────────────────────┐
│                     IMPORTANT: mkinitcpio Configuration                      │
├──────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│  After running archinstall or pacstrap, you MUST configure mkinitcpio!      │
│                                                                              │
│  Edit /etc/mkinitcpio.conf and modify the HOOKS line:                        │
│                                                                              │
│  BEFORE:                                                                     │
│  HOOKS=(base udev autodetect modconf kms keyboard keymap consolefont        │
│         block filesystems fsck)                                              │
│                                                                              │
│  AFTER:                                                                      │
│  HOOKS=(base udev autodetect modconf kms keyboard keymap consolefont        │
│         block zfs filesystems)                                               │
│                                                                              │
│  Note: Add 'zfs' before 'filesystems' and remove 'fsck'                      │
│                                                                              │
│  Then regenerate initramfs:                                                  │
│    mkinitcpio -P                                                             │
│                                                                              │
└──────────────────────────────────────────────────────────────────────────────┘

EOF
}

print_next_steps() {
    local pool_name="$1"
    local disk="$2"

    cat << EOF

┌──────────────────────────────────────────────────────────────────────────────┐
│                     ZFS Pre-Install Setup Complete!                          │
├──────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│  Pool: $pool_name
│  Disk: $disk
│  ZFS Partition: $ZFS_PART_BYID
│                                                                              │
│  Next steps:                                                                 │
│                                                                              │
│  1. Run archinstall with your ZFS config:                                    │
│     archinstall --config user_configuration.json --creds user_credentials.json
│                                                                              │
│  2. Or continue manually with pacstrap:                                      │
│     pacstrap -K /mnt base linux linux-zen linux-firmware                     │
│     pacstrap -K /mnt zfs-linux zfs-linux-zen zfs-utils                       │
│                                                                              │
│  3. Generate fstab (for /boot only - ZFS mounts via zfs.target):             │
│     genfstab -U /mnt | grep boot >> /mnt/etc/fstab                           │
│                                                                              │
│  4. Chroot and configure:                                                    │
│     arch-chroot /mnt                                                         │
│                                                                              │
│  5. IMPORTANT: Configure mkinitcpio (see instructions above!)                │
│                                                                              │
│  6. Enable ZFS services:                                                     │
│     systemctl enable zfs.target                                              │
│     systemctl enable zfs-import-cache.service                                │
│     systemctl enable zfs-mount.service                                       │
│                                                                              │
│  7. Install bootloader (systemd-boot):                                       │
│     bootctl install                                                          │
│     # Create boot entry with: root=zfs=$pool_name/root rw                    │
│                                                                              │
│  8. After install, run the Hyprland setup script:                            │
│     curl -fsSL https://raw.githubusercontent.com/danielbodnar/archconfigs/   │
│       main/scripts/xps9500-hyprland-setup.sh | sudo bash                     │
│                                                                              │
└──────────────────────────────────────────────────────────────────────────────┘

EOF
}

show_summary() {
    echo ""
    echo "═══════════════════════════════════════════════════════════════════════════════"
    echo "                           Installation Summary"
    echo "═══════════════════════════════════════════════════════════════════════════════"
    echo ""
    printf "  Pool Name:      ${GREEN}%s${NC}\n" "$POOL_NAME"
    printf "  Disk:           ${GREEN}%s${NC}\n" "$DISK"
    printf "  Swap Size:      ${GREEN}%s GB${NC}\n" "$SWAP_SIZE"
    printf "  GitHub User:    ${GREEN}%s${NC}\n" "$GITHUB_USER"
    echo ""
    echo "═══════════════════════════════════════════════════════════════════════════════"
    echo ""

    read -rp "Proceed with installation? [y/N]: " confirm
    if [[ "${confirm,,}" != "y" ]]; then
        info "Installation cancelled"
        exit 0
    fi
}

main() {
    echo ""
    printf "${BLUE}╔══════════════════════════════════════════════════════════════════════════════╗${NC}\n"
    printf "${BLUE}║${NC}              Dell XPS 15 9500 - ZFS Pre-Install Script                       ${BLUE}║${NC}\n"
    printf "${BLUE}║${NC}              Following OpenZFS Arch Linux Root on ZFS Guide                  ${BLUE}║${NC}\n"
    printf "${BLUE}╚══════════════════════════════════════════════════════════════════════════════╝${NC}\n"
    echo ""

    check_archiso
    check_uefi

    # Interactive prompts
    prompt_for_disk
    prompt_for_pool_name
    prompt_for_swap_size
    prompt_for_github_user

    # Show summary and confirm
    show_summary

    # Run installation
    setup_zfs_archiso
    setup_archzfs_repo
    partition_disk "$DISK" "$SWAP_SIZE"
    create_zfs_pool "$POOL_NAME" "$ZFS_PART_BYID"
    create_zfs_datasets "$POOL_NAME"
    mount_filesystems "$POOL_NAME"
    generate_hostid
    create_zfs_cache
    fetch_ssh_keys "$GITHUB_USER"

    print_mkinitcpio_instructions
    print_next_steps "$POOL_NAME" "$DISK"

    success "Pre-install setup complete!"
}

# Allow sourcing without execution
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
