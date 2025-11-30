#!/usr/bin/env bash
# Dell XPS 15 9500 Driver & Hardware Configuration for Hyprland
# https://github.com/danielbodnar/archconfigs/tree/main/scripts/xps9500-hyprland-setup.sh
#
# Hardware: Intel i7-10750H, NVIDIA GTX 1650 Ti, Intel UHD 630, Killer Wi-Fi 6 AX1650
# Run as root after base Arch install with Hyprland
#
# Usage:
#   curl -fsSL https://raw.githubusercontent.com/danielbodnar/archconfigs/main/scripts/xps9500-hyprland-setup.sh | sudo bash

set -euo pipefail

readonly SCRIPT_NAME="${0##*/}"
readonly LOG_FILE="/var/log/xps9500-setup.log"
readonly GITHUB_USER="${GITHUB_SSH_USER:-danielbodnar}"

log() { printf '[%s] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*" | tee -a "$LOG_FILE"; }
info() { log "INFO: $*"; }
warn() { log "WARN: $*"; }
error() { log "ERROR: $*"; exit 1; }

check_root() {
    [[ $EUID -eq 0 ]] || error "This script must be run as root"
}

check_xps9500() {
    local product
    product=$(cat /sys/class/dmi/id/product_name 2>/dev/null || echo "unknown")
    if [[ "$product" != *"XPS 15 9500"* ]]; then
        warn "This script is designed for Dell XPS 15 9500"
        warn "Detected: $product"
        read -rp "Continue anyway? [y/N] " confirm
        [[ "${confirm,,}" == "y" ]] || exit 0
    fi
}

install_packages() {
    info "Installing driver packages..."
    
    pacman -S --needed --noconfirm \
        linux-headers \
        linux-zen-headers \
        nvidia-dkms \
        nvidia-utils \
        lib32-nvidia-utils \
        nvidia-settings \
        nvidia-prime \
        libva-nvidia-driver \
        vulkan-icd-loader \
        lib32-vulkan-icd-loader \
        mesa \
        lib32-mesa \
        vulkan-intel \
        lib32-vulkan-intel \
        intel-media-driver \
        libva-intel-driver \
        intel-gpu-tools \
        thermald \
        powertop \
        power-profiles-daemon \
        fwupd \
        iio-sensor-proxy \
        bluez \
        bluez-utils \
        pipewire \
        pipewire-pulse \
        pipewire-alsa \
        pipewire-jack \
        wireplumber \
        sof-firmware \
        alsa-ucm-conf \
        brightnessctl \
        playerctl \
        pamixer \
        qt5-wayland \
        qt6-wayland \
        xdg-desktop-portal-hyprland \
        xdg-desktop-portal-gtk \
        polkit-gnome \
        libinput \
        xf86-input-libinput
}

configure_nvidia_kernel() {
    info "Configuring NVIDIA kernel modules..."
    
    local mkinitcpio_conf="/etc/mkinitcpio.conf"
    if ! grep -q "nvidia nvidia_modeset nvidia_uvm nvidia_drm" "$mkinitcpio_conf"; then
        # Intel iGPU first to prevent Electron app hangs
        sed -i 's/^MODULES=(\(.*\))/MODULES=(i915 nvidia nvidia_modeset nvidia_uvm nvidia_drm \1)/' "$mkinitcpio_conf"
        info "Added NVIDIA modules to mkinitcpio.conf"
    fi
    
    # Enable DRM modesetting
    mkdir -p /etc/modprobe.d
    cat > /etc/modprobe.d/nvidia.conf << 'EOF'
options nvidia_drm modeset=1 fbdev=1
options nvidia NVreg_PreserveVideoMemoryAllocations=1
options nvidia NVreg_TemporaryFilePath=/var/tmp
EOF
    info "Created /etc/modprobe.d/nvidia.conf"
    
    mkinitcpio -P
}

configure_bootloader() {
    info "Configuring systemd-boot kernel parameters..."
    
    local loader_entries="/boot/loader/entries"
    
    for entry in "$loader_entries"/*.conf; do
        [[ -f "$entry" ]] || continue
        
        local params="nvidia_drm.modeset=1 nvidia_drm.fbdev=1 nvidia.NVreg_PreserveVideoMemoryAllocations=1"
        
        if ! grep -q "nvidia_drm.modeset=1" "$entry"; then
            sed -i "/^options/ s/$/ $params/" "$entry"
            info "Updated $entry with NVIDIA kernel parameters"
        fi
    done
}

configure_nvidia_power() {
    info "Configuring NVIDIA power management..."
    
    systemctl enable nvidia-suspend.service
    systemctl enable nvidia-hibernate.service
    systemctl enable nvidia-resume.service
    
    mkdir -p /etc/udev/rules.d
    cat > /etc/udev/rules.d/80-nvidia-pm.rules << 'EOF'
# Enable runtime PM for NVIDIA VGA/3D controller
ACTION=="add", SUBSYSTEM=="pci", ATTR{vendor}=="0x10de", ATTR{class}=="0x030000", ATTR{power/control}="auto"
ACTION=="add", SUBSYSTEM=="pci", ATTR{vendor}=="0x10de", ATTR{class}=="0x030200", ATTR{power/control}="auto"

# Remove NVIDIA USB xHCI Host Controller
ACTION=="add", SUBSYSTEM=="pci", ATTR{vendor}=="0x10de", ATTR{class}=="0x0c0330", ATTR{remove}="1"

# Remove NVIDIA USB Type-C UCSI devices
ACTION=="add", SUBSYSTEM=="pci", ATTR{vendor}=="0x10de", ATTR{class}=="0x0c8000", ATTR{remove}="1"

# Remove NVIDIA Audio devices
ACTION=="add", SUBSYSTEM=="pci", ATTR{vendor}=="0x10de", ATTR{class}=="0x040300", ATTR{remove}="1"
EOF
    info "Created NVIDIA power management udev rules"
}

configure_hyprland_nvidia() {
    info "Creating Hyprland NVIDIA environment configuration..."
    
    mkdir -p /etc/hypr
    cat > /etc/hypr/nvidia.conf << 'EOF'
# Dell XPS 15 9500 NVIDIA configuration for Hyprland
# Source this from your hyprland.conf: source = /etc/hypr/nvidia.conf

env = LIBVA_DRIVER_NAME,nvidia
env = XDG_SESSION_TYPE,wayland
env = GBM_BACKEND,nvidia-drm
env = __GLX_VENDOR_LIBRARY_NAME,nvidia
env = NVD_BACKEND,direct

# Cursor fix for NVIDIA
env = WLR_NO_HARDWARE_CURSORS,1

# Explicit sync (newer kernels/drivers)
env = __GL_ExperimentalPerfStrategy,1

# For multi-GPU setups - uncomment if needed
# env = AQ_DRM_DEVICES,/dev/dri/card1:/dev/dri/card0

# Electron/Chromium Wayland flags
env = ELECTRON_OZONE_PLATFORM_HINT,auto
env = NIXOS_OZONE_WL,1

# Qt Wayland
env = QT_QPA_PLATFORM,wayland;xcb
env = QT_WAYLAND_DISABLE_WINDOWDECORATION,1

# SDL
env = SDL_VIDEODRIVER,wayland

# Clutter
env = CLUTTER_BACKEND,wayland
EOF
    info "Created /etc/hypr/nvidia.conf"
    
    mkdir -p /etc/skel/.config/hypr
    cat > /etc/skel/.config/hypr/README-nvidia.md << 'EOF'
# NVIDIA Configuration for Hyprland

Add this line to your ~/.config/hypr/hyprland.conf:

```
source = /etc/hypr/nvidia.conf
```

## Troubleshooting

### Firefox crashes
Remove or comment out: `env = GBM_BACKEND,nvidia-drm`

### Discord/Zoom screen share issues
Remove or comment out: `env = __GLX_VENDOR_LIBRARY_NAME,nvidia`

### Multi-monitor flickering
Try adding: `env = AQ_FORCE_LINEAR_BLIT,0`

### Running specific apps on NVIDIA GPU
Use: `prime-run <application>`
EOF
    info "Created NVIDIA README for users"
}

configure_touchpad() {
    info "Configuring touchpad for libinput..."
    
    # XWayland touchpad config
    mkdir -p /etc/X11/xorg.conf.d
    cat > /etc/X11/xorg.conf.d/30-touchpad.conf << 'EOF'
# Dell XPS 15 9500 touchpad configuration
# This is for XWayland apps - Hyprland handles this natively
Section "InputClass"
    Identifier "touchpad"
    MatchIsTouchpad "on"
    Driver "libinput"
    Option "Tapping" "on"
    Option "TappingButtonMap" "lrm"
    Option "NaturalScrolling" "on"
    Option "ScrollMethod" "twofinger"
    Option "ClickMethod" "clickfinger"
    Option "DisableWhileTyping" "on"
    Option "AccelProfile" "adaptive"
EndSection
EOF
    
    # Disable i2c power management to prevent touchpad lag
    cat > /etc/udev/rules.d/99-i2c-touchpad.rules << 'EOF'
# Disable i2c power management to prevent ELAN touchpad lag
# XPS 9500 touchpad shares i2c bus with touchscreen
ACTION=="add", SUBSYSTEM=="i2c", ATTR{power/control}="on"

# Keep ELAN touchpad powered
ACTION=="add", SUBSYSTEM=="hid", ATTRS{idVendor}=="04f3", ATTRS{idProduct}=="311c", ATTR{power/control}="on"
EOF
    
    info "Touchpad configuration complete"
}

configure_touchpad_firmware() {
    info "Checking touchpad firmware..."
    
    # Check if fwupd is available
    if ! command -v fwupdmgr &>/dev/null; then
        warn "fwupd not installed - skipping firmware check"
        return
    fi
    
    # Refresh firmware metadata
    fwupdmgr refresh --force 2>/dev/null || true
    
    # Check for touchpad
    local touchpad_info
    touchpad_info=$(fwupdmgr get-devices 2>/dev/null | grep -A10 -i "touchpad" || true)
    
    if [[ -n "$touchpad_info" ]]; then
        info "Touchpad detected:"
        echo "$touchpad_info" | head -10
        
        # Check for updates
        local updates
        updates=$(fwupdmgr get-updates 2>/dev/null | grep -i "touchpad" || true)
        
        if [[ -n "$updates" ]]; then
            info "Touchpad firmware update available!"
            echo "$updates"
        fi
    fi
    
    # Create firmware update script for manual use
    cat > /usr/local/bin/update-touchpad-firmware << 'SCRIPT'
#!/usr/bin/env bash
# Dell XPS 9500 ELAN Touchpad Firmware Update
# Fixes laggy/jumpy touchpad issues
#
# Firmware versions:
#   0b - Initial fix for touch jump issues
#   0c - Latest recommended version
#
# Manual firmware available at:
# https://gist.github.com/m-bartlett/78d0748b279b7c4c2efd9c93c7496405

set -euo pipefail

echo "Checking for touchpad firmware updates..."

# Try fwupd first
if fwupdmgr get-updates 2>/dev/null | grep -qi touchpad; then
    echo "Firmware update available via fwupd"
    read -rp "Install update? [y/N] " confirm
    if [[ "${confirm,,}" == "y" ]]; then
        fwupdmgr update
    fi
else
    echo "No updates via fwupd."
    echo ""
    echo "For manual firmware update (version 0c), see:"
    echo "https://gist.github.com/m-bartlett/78d0748b279b7c4c2efd9c93c7496405"
    echo ""
    echo "Or download directly from Dell:"
    echo "https://www.dell.com/support/home/drivers/driversdetails?driverid=1cdn7"
fi
SCRIPT
    chmod +x /usr/local/bin/update-touchpad-firmware
    
    info "Created /usr/local/bin/update-touchpad-firmware helper script"
}

configure_audio() {
    info "Configuring audio (Intel HDA + SOF)..."
    
    mkdir -p /etc/modprobe.d
    cat > /etc/modprobe.d/audio.conf << 'EOF'
# Dell XPS 15 9500 audio fixes
# Fix combo jack headset detection
options snd-hda-intel model=auto
options snd-hda-intel dmic_detect=0
EOF
    
    systemctl --global enable pipewire.socket
    systemctl --global enable pipewire-pulse.socket
    systemctl --global enable wireplumber.service
    
    info "Audio configuration complete"
}

configure_power() {
    info "Configuring power management..."
    
    systemctl enable thermald.service
    systemctl enable power-profiles-daemon.service
    
    # powertop auto-tune service
    cat > /etc/systemd/system/powertop.service << 'EOF'
[Unit]
Description=Powertop auto-tune
After=multi-user.target

[Service]
Type=oneshot
ExecStart=/usr/bin/powertop --auto-tune
RemainAfterExit=true

[Install]
WantedBy=multi-user.target
EOF
    systemctl enable powertop.service
    
    info "Power management configuration complete"
}

configure_bluetooth() {
    info "Configuring Bluetooth..."
    
    systemctl enable bluetooth.service
    
    mkdir -p /etc/bluetooth
    if [[ -f /etc/bluetooth/main.conf ]]; then
        sed -i 's/^#FastConnectable.*/FastConnectable = true/' /etc/bluetooth/main.conf
        sed -i 's/^#ReconnectAttempts.*/ReconnectAttempts = 7/' /etc/bluetooth/main.conf
        sed -i 's/^#ReconnectIntervals.*/ReconnectIntervals = 1, 2, 4, 8, 16, 32, 64/' /etc/bluetooth/main.conf
    fi
    
    info "Bluetooth configuration complete"
}

configure_firmware_updates() {
    info "Configuring firmware updates via fwupd..."
    
    systemctl enable fwupd-refresh.timer
    
    mkdir -p /etc/fwupd/remotes.d
    cat > /etc/fwupd/remotes.d/lvfs-testing.conf << 'EOF'
[fwupd Remote]
Enabled=true
Title=Linux Vendor Firmware Service (testing)
MetadataURI=https://cdn.fwupd.org/downloads/firmware-testing.xml.gz
ReportURI=https://fwupd.org/lvfs/firmware/report
EOF
    
    info "fwupd configuration complete"
}

configure_sensors() {
    info "Configuring sensors (accelerometer, ambient light)..."
    
    systemctl enable iio-sensor-proxy.service
    
    info "Sensor configuration complete"
}

setup_ssh_keys() {
    info "Setting up SSH keys from GitHub..."
    
    local target_user
    target_user="${SUDO_USER:-}"
    if [[ -z "$target_user" ]]; then
        target_user=$(getent passwd 1000 | cut -d: -f1 || echo "")
    fi
    
    if [[ -n "$target_user" ]]; then
        local home_dir
        home_dir=$(getent passwd "$target_user" | cut -d: -f6)
        local ssh_dir="$home_dir/.ssh"
        
        mkdir -p "$ssh_dir"
        
        if curl -fsSL "https://github.com/${GITHUB_USER}.keys" > "$ssh_dir/authorized_keys" 2>/dev/null; then
            chmod 700 "$ssh_dir"
            chmod 600 "$ssh_dir/authorized_keys"
            chown -R "$target_user:$target_user" "$ssh_dir"
            info "SSH keys installed for $target_user from github.com/$GITHUB_USER"
        else
            warn "Failed to fetch SSH keys from GitHub"
        fi
    else
        warn "No target user found for SSH key installation"
    fi
}

print_post_install() {
    cat << 'EOF'

╔══════════════════════════════════════════════════════════════════════════════╗
║              Dell XPS 15 9500 Setup Complete!                                ║
╠══════════════════════════════════════════════════════════════════════════════╣
║                                                                              ║
║  REQUIRED: Reboot your system for all changes to take effect                 ║
║                                                                              ║
║  BIOS Settings (press F2 at boot):                                           ║
║  • SATA Mode: AHCI (not RAID)                                                ║
║  • Fastboot: Thorough                                                        ║
║  • Secure Boot: Disabled (or configure for Linux)                            ║
║                                                                              ║
║  Hyprland Configuration:                                                     ║
║  Add to ~/.config/hypr/hyprland.conf:                                        ║
║    source = /etc/hypr/nvidia.conf                                            ║
║                                                                              ║
║  Useful Commands:                                                            ║
║  • prime-run <app>              - Run app on NVIDIA GPU                      ║
║  • nvidia-smi                   - Check NVIDIA GPU status                    ║
║  • powerprofilesctl             - Switch power profiles                      ║
║  • brightnessctl                - Control screen brightness                  ║
║  • fwupdmgr get-updates         - Check for firmware updates                 ║
║  • update-touchpad-firmware     - Check/update touchpad firmware             ║
║                                                                              ║
║  Touchpad Issues?                                                            ║
║  • Run: update-touchpad-firmware                                             ║
║  • Manual firmware: https://gist.github.com/m-bartlett/78d0748b279b7c4c2efd  ║
║                                                                              ║
║  Known Limitations:                                                          ║
║  • Fingerprint reader not supported on Linux                                 ║
║  • Deep sleep (S3) may have issues - s2idle works                            ║
║                                                                              ║
║  Log file: /var/log/xps9500-setup.log                                        ║
╚══════════════════════════════════════════════════════════════════════════════╝

EOF
}

main() {
    info "Starting Dell XPS 15 9500 setup for Hyprland"
    
    check_root
    check_xps9500
    
    install_packages
    configure_nvidia_kernel
    configure_bootloader
    configure_nvidia_power
    configure_hyprland_nvidia
    configure_touchpad
    configure_touchpad_firmware
    configure_audio
    configure_power
    configure_bluetooth
    configure_firmware_updates
    configure_sensors
    setup_ssh_keys
    
    print_post_install
    
    info "Setup complete! Please reboot."
}

# Allow sourcing without execution
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
