#!/usr/bin/env bash
# ZFS Post-Install Configuration Script
# https://github.com/danielbodnar/archconfigs/tree/main/scripts/zfs-postinstall.sh
#
# Run inside arch-chroot after pacstrap/archinstall to configure ZFS boot:
#   arch-chroot /mnt
#   curl -fsSL https://raw.githubusercontent.com/danielbodnar/archconfigs/main/scripts/zfs-postinstall.sh | bash
#
# This script:
# - Configures mkinitcpio hooks for ZFS
# - Generates hostid if missing
# - Creates systemd-boot entries for ZFS
# - Enables ZFS services

set -euo pipefail

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

check_root() {
    [[ $EUID -eq 0 ]] || error "This script must be run as root"
}

check_zfs_installed() {
    if ! command -v zfs &>/dev/null; then
        error "ZFS is not installed. Install zfs-linux and zfs-utils first."
    fi
}

detect_pool_name() {
    # Try to detect pool name from bootfs property
    local bootfs
    bootfs=$(zpool get -H -o value bootfs 2>/dev/null | head -1 || true)

    if [[ -n "$bootfs" && "$bootfs" != "-" ]]; then
        POOL_NAME="${bootfs%%/*}"
        info "Detected ZFS pool: $POOL_NAME"
        return
    fi

    # Try to find any imported pool
    POOL_NAME=$(zpool list -H -o name 2>/dev/null | head -1 || true)

    if [[ -n "$POOL_NAME" ]]; then
        info "Found ZFS pool: $POOL_NAME"
        return
    fi

    # Ask user
    echo ""
    printf "${YELLOW}Enter your ZFS pool name:${NC}\n"
    read -rp "Pool name: " POOL_NAME

    if [[ -z "$POOL_NAME" ]]; then
        error "Pool name is required"
    fi
}

configure_mkinitcpio() {
    info "Configuring mkinitcpio for ZFS..."

    local conf="/etc/mkinitcpio.conf"

    if [[ ! -f "$conf" ]]; then
        error "mkinitcpio.conf not found at $conf"
    fi

    # Backup original
    cp "$conf" "${conf}.backup.$(date +%Y%m%d%H%M%S)"

    # Read current HOOKS line
    local current_hooks
    current_hooks=$(grep "^HOOKS=" "$conf" || true)

    if [[ -z "$current_hooks" ]]; then
        warn "No HOOKS line found in mkinitcpio.conf"
        return
    fi

    info "Current HOOKS: $current_hooks"

    # Check if zfs is already in hooks
    if echo "$current_hooks" | grep -q '\bzfs\b'; then
        info "ZFS hook already configured"
    else
        # Add zfs before filesystems
        if echo "$current_hooks" | grep -q '\bfilesystems\b'; then
            sed -i 's/\bfilesystems\b/zfs filesystems/' "$conf"
            info "Added 'zfs' hook before 'filesystems'"
        else
            warn "Could not find 'filesystems' in HOOKS, adding zfs manually"
            sed -i 's/^HOOKS=(\(.*\))/HOOKS=(\1 zfs)/' "$conf"
        fi
    fi

    # Remove fsck hook (not needed for ZFS)
    if grep -q '\bfsck\b' "$conf"; then
        sed -i 's/\bfsck\b//' "$conf"
        # Clean up double spaces
        sed -i 's/  \+/ /g' "$conf"
        sed -i 's/( /(/g' "$conf"
        sed -i 's/ )/)/g' "$conf"
        info "Removed 'fsck' hook (not needed for ZFS)"
    fi

    # Show new configuration
    local new_hooks
    new_hooks=$(grep "^HOOKS=" "$conf")
    success "New HOOKS: $new_hooks"
}

generate_hostid() {
    info "Checking ZFS hostid..."

    if [[ -f /etc/hostid ]]; then
        info "Hostid already exists: $(cat /etc/hostid | xxd -p 2>/dev/null || echo "present")"
    else
        info "Generating new hostid..."
        zgenhostid -f
        success "Hostid generated: $(cat /etc/hostid | xxd -p 2>/dev/null || echo "generated")"
    fi
}

regenerate_initramfs() {
    info "Regenerating initramfs..."

    mkinitcpio -P

    success "Initramfs regenerated for all kernels"
}

enable_zfs_services() {
    info "Enabling ZFS services..."

    systemctl enable zfs.target
    systemctl enable zfs-import-cache.service
    systemctl enable zfs-mount.service
    systemctl enable zfs-import.target

    success "ZFS services enabled"
}

configure_systemd_boot() {
    local loader_entries="/boot/loader/entries"

    if [[ ! -d "$loader_entries" ]]; then
        info "systemd-boot entries directory not found, skipping boot entry configuration"
        return
    fi

    info "Configuring systemd-boot entries for ZFS..."

    # Get root dataset
    local root_dataset="${POOL_NAME}/root"

    # Check for existing entries
    for entry in "$loader_entries"/*.conf; do
        [[ -f "$entry" ]] || continue

        local entry_name
        entry_name=$(basename "$entry")

        # Check if this entry already has ZFS root
        if grep -q "root=zfs=" "$entry"; then
            info "Entry $entry_name already configured for ZFS"
            continue
        fi

        # Check if it has a root= option
        if grep -q "^options.*root=" "$entry"; then
            # Update existing root option
            sed -i "s|root=[^ ]*|root=zfs=${root_dataset}|" "$entry"
            info "Updated $entry_name with ZFS root"
        else
            # Add root option if options line exists
            if grep -q "^options" "$entry"; then
                sed -i "s|^options.*|& root=zfs=${root_dataset} rw|" "$entry"
                info "Added ZFS root to $entry_name"
            fi
        fi
    done

    success "systemd-boot configuration complete"
}

create_zfs_boot_entry() {
    local loader_entries="/boot/loader/entries"

    if [[ ! -d "$loader_entries" ]]; then
        mkdir -p "$loader_entries"
    fi

    # Find installed kernels
    local kernels=()
    [[ -f /boot/vmlinuz-linux ]] && kernels+=("linux")
    [[ -f /boot/vmlinuz-linux-zen ]] && kernels+=("linux-zen")
    [[ -f /boot/vmlinuz-linux-lts ]] && kernels+=("linux-lts")

    if [[ ${#kernels[@]} -eq 0 ]]; then
        warn "No kernels found in /boot"
        return
    fi

    local root_dataset="${POOL_NAME}/root"

    for kernel in "${kernels[@]}"; do
        local entry_file="$loader_entries/${kernel}-zfs.conf"

        # Skip if entry already exists
        if [[ -f "$entry_file" ]]; then
            info "Entry $entry_file already exists"
            continue
        fi

        # Detect microcode
        local initrd_lines=""
        [[ -f /boot/intel-ucode.img ]] && initrd_lines="initrd  /intel-ucode.img"$'\n'
        [[ -f /boot/amd-ucode.img ]] && initrd_lines="initrd  /amd-ucode.img"$'\n'

        cat > "$entry_file" << EOF
title   Arch Linux (${kernel}, ZFS)
linux   /vmlinuz-${kernel}
${initrd_lines}initrd  /initramfs-${kernel}.img
options root=zfs=${root_dataset} rw zfs_import_dir=/dev/
EOF

        info "Created boot entry: $entry_file"
    done

    # Update default entry
    local loader_conf="/boot/loader/loader.conf"
    if [[ -f "$loader_conf" ]]; then
        # Check if default is set
        if ! grep -q "^default" "$loader_conf"; then
            echo "default ${kernels[0]}-zfs.conf" >> "$loader_conf"
            info "Set default boot entry to ${kernels[0]}-zfs.conf"
        fi
    fi

    success "ZFS boot entries created"
}

configure_zfs_cache() {
    info "Configuring ZFS cache..."

    mkdir -p /etc/zfs

    # Set cachefile
    if zpool list "$POOL_NAME" &>/dev/null; then
        zpool set cachefile=/etc/zfs/zpool.cache "$POOL_NAME"
        success "ZFS cache file configured"
    else
        warn "Pool $POOL_NAME not available, skipping cache configuration"
    fi
}

print_summary() {
    cat << EOF

┌──────────────────────────────────────────────────────────────────────────────┐
│                   ZFS Post-Install Configuration Complete!                   │
├──────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│  Pool: $POOL_NAME
│  Root Dataset: ${POOL_NAME}/root
│                                                                              │
│  Configured:                                                                 │
│  - mkinitcpio hooks (zfs before filesystems)                                 │
│  - ZFS hostid (/etc/hostid)                                                  │
│  - ZFS services (zfs.target, zfs-import-cache, zfs-mount)                    │
│  - systemd-boot entries                                                      │
│                                                                              │
│  Next steps:                                                                 │
│  1. Set root password: passwd                                                │
│  2. Create user: useradd -m -G wheel username                                │
│  3. Exit chroot: exit                                                        │
│  4. Unmount and export:                                                      │
│     umount -Rl /mnt                                                          │
│     zpool export $POOL_NAME
│  5. Reboot!                                                                  │
│                                                                              │
└──────────────────────────────────────────────────────────────────────────────┘

EOF
}

main() {
    echo ""
    printf "${BLUE}╔══════════════════════════════════════════════════════════════════════════════╗${NC}\n"
    printf "${BLUE}║${NC}              ZFS Post-Install Configuration Script                           ${BLUE}║${NC}\n"
    printf "${BLUE}╚══════════════════════════════════════════════════════════════════════════════╝${NC}\n"
    echo ""

    check_root
    check_zfs_installed
    detect_pool_name
    configure_mkinitcpio
    generate_hostid
    regenerate_initramfs
    enable_zfs_services
    configure_zfs_cache
    configure_systemd_boot
    create_zfs_boot_entry
    print_summary

    success "ZFS post-install configuration complete!"
}

# Allow sourcing without execution
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
