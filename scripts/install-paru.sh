#!/usr/bin/env bash
# Install paru AUR helper
# https://github.com/danielbodnar/archconfigs/tree/main/scripts/install-paru.sh
#
# Run as a regular user (not root):
#   curl -fsSL https://raw.githubusercontent.com/danielbodnar/archconfigs/main/scripts/install-paru.sh | bash
#
# Or download and run:
#   curl -fsSLO https://raw.githubusercontent.com/danielbodnar/archconfigs/main/scripts/install-paru.sh
#   chmod +x install-paru.sh
#   ./install-paru.sh

set -euo pipefail

readonly BUILD_DIR="${PARU_BUILD_DIR:-/tmp/paru-build}"

log() { printf '\033[1;34m[%s]\033[0m %s\n' "$(date '+%H:%M:%S')" "$*"; }
info() { log "INFO: $*"; }
warn() { printf '\033[1;33m[%s] WARN:\033[0m %s\n' "$(date '+%H:%M:%S')" "$*"; }
error() { printf '\033[1;31m[%s] ERROR:\033[0m %s\n' "$(date '+%H:%M:%S')" "$*"; exit 1; }

check_not_root() {
    if [[ $EUID -eq 0 ]]; then
        error "This script must NOT be run as root. Run as your regular user."
    fi
}

check_arch_linux() {
    if [[ ! -f /etc/arch-release ]]; then
        error "This script is designed for Arch Linux"
    fi
}

check_sudo() {
    if ! command -v sudo &>/dev/null; then
        error "sudo is required but not installed"
    fi

    # Test sudo access
    if ! sudo -v; then
        error "Cannot acquire sudo privileges"
    fi
}

install_dependencies() {
    info "Installing build dependencies..."

    sudo pacman -S --needed --noconfirm \
        base-devel \
        git \
        rustup

    # Initialize rustup if needed
    if ! rustup show active-toolchain &>/dev/null; then
        info "Initializing Rust toolchain..."
        rustup default stable
    fi

    info "Dependencies installed"
}

install_paru() {
    if command -v paru &>/dev/null; then
        info "paru is already installed"
        paru --version
        return 0
    fi

    info "Building paru from AUR..."

    # Clean up any previous build
    rm -rf "$BUILD_DIR"
    mkdir -p "$BUILD_DIR"

    # Clone paru from AUR
    git clone https://aur.archlinux.org/paru.git "$BUILD_DIR"

    # Build and install
    pushd "$BUILD_DIR" > /dev/null
    makepkg -si --noconfirm
    popd > /dev/null

    # Clean up
    rm -rf "$BUILD_DIR"

    info "paru installed successfully"
    paru --version
}

configure_paru() {
    info "Configuring paru..."

    local paru_conf="/etc/paru.conf"

    # Create user config directory
    mkdir -p ~/.config/paru

    # Create user paru.conf with recommended settings
    cat > ~/.config/paru/paru.conf << 'EOF'
#
# paru configuration
#

[options]
# Use sudo for privilege escalation
Sudo = sudo

# Build packages in /tmp
BuildDir = /tmp/paru-build

# Clean build directory after install
CleanAfter

# Show diffs before building
DevelSuffixes = -git -cvs -svn -bzr -darcs -always -hg -fossil

# Provides support - search for packages providing a file
Provides

# Use batch install for faster dependency installation
BatchInstall

# Color output
Color

# Show news from archlinux.org
NewsOnUpgrade

# Remove make dependencies after building
RemoveMake
EOF

    info "Created ~/.config/paru/paru.conf"
}

print_usage() {
    cat << 'EOF'

┌──────────────────────────────────────────────────────────────────────────────┐
│                        paru AUR Helper Installed!                            │
├──────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│  Usage:                                                                      │
│    paru <package>           - Search and install package (AUR + official)   │
│    paru -S <package>        - Install package                                │
│    paru -Ss <query>         - Search for packages                            │
│    paru -Syu                - Update all packages (including AUR)            │
│    paru -Sua                - Update only AUR packages                       │
│    paru -Qua                - List AUR packages with updates                 │
│    paru -c                  - Clean unneeded dependencies                    │
│    paru -G <package>        - Get PKGBUILD from AUR (don't install)          │
│                                                                              │
│  Installing yay (another AUR helper):                                        │
│    paru -S yay              - Install yay from AUR                           │
│                                                                              │
│  Configuration:                                                              │
│    ~/.config/paru/paru.conf                                                  │
│                                                                              │
│  More info: https://github.com/Morganamilo/paru                              │
│                                                                              │
└──────────────────────────────────────────────────────────────────────────────┘

EOF
}

main() {
    info "Installing paru AUR helper"

    check_not_root
    check_arch_linux
    check_sudo
    install_dependencies
    install_paru
    configure_paru
    print_usage

    info "Installation complete!"
}

# Allow sourcing without execution
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
