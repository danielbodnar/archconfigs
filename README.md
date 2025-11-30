# archconfigs

Arch Linux automated installation configurations with netboot.xyz integration, optimized for Dell XPS 15 9500 with ZFS and Hyprland.

## Overview

This repository provides:
- **archinstall configurations**: JSON configuration files for automated Arch Linux installations with ZFS
- **netboot.xyz integration**: Custom iPXE menus for network booting Arch Linux
- **Dell XPS 15 9500 scripts**: Pre-install and post-install setup scripts
- **dotfiles**: System configuration files for NVIDIA, Hyprland, touchpad, etc.

## Directory Structure

```
├── archinstall/                          # Archinstall configuration files
│   ├── user_configuration.json           # System config (ZFS, Hyprland, packages)
│   └── user_credentials.json             # User accounts and passwords
├── dotfiles/                             # System configuration files
│   ├── hypr/
│   │   └── nvidia.conf                   # Hyprland NVIDIA environment vars
│   └── etc/
│       ├── modprobe.d/
│       │   ├── nvidia.conf               # NVIDIA kernel module options
│       │   └── audio.conf                # Audio fixes
│       ├── X11/xorg.conf.d/
│       │   └── 30-touchpad.conf          # Touchpad configuration
│       └── udev/rules.d/
│           ├── 80-nvidia-pm.rules        # NVIDIA power management
│           └── 99-i2c-touchpad.rules     # Touchpad power management
├── netboot/                              # Netboot.xyz files
│   ├── custom.ipxe                       # Custom iPXE menu for Arch Linux
│   └── boot.cfg                          # Boot configuration
├── scripts/                              # Helper scripts
│   ├── dell-xps-init.sh                  # ZFS pre-install script
│   ├── xps9500-hyprland-setup.sh         # Post-install driver setup
│   ├── validate-configs.sh               # Validate JSON configuration files
│   └── generate-config-url.sh            # Generate URLs for archinstall
└── README.md
```

## Quick Start - Dell XPS 15 9500

### Step 1: Pre-Install (ZFS Setup)

Boot into the Arch Linux ISO and run:

```bash
curl -fsSL https://raw.githubusercontent.com/danielbodnar/archconfigs/main/scripts/dell-xps-init.sh | bash
```

This script:
- Installs ZFS on archiso
- Partitions the disk (1GB EFI + ZFS)
- Creates ZFS pool with optimal settings
- Creates ZFS datasets (ROOT, home, var)
- Mounts filesystems at /mnt

### Step 2: Run archinstall

```bash
archinstall --config https://raw.githubusercontent.com/danielbodnar/archconfigs/main/archinstall/user_configuration.json
```

### Step 3: Post-Install (Drivers & Hardware)

After first boot, run:

```bash
curl -fsSL https://raw.githubusercontent.com/danielbodnar/archconfigs/main/scripts/xps9500-hyprland-setup.sh | sudo bash
```

This script:
- Installs NVIDIA drivers (dkms)
- Configures hybrid graphics
- Sets up Hyprland for NVIDIA
- Configures touchpad, audio, Bluetooth
- Sets up power management

### Step 4: Configure Hyprland

Add to `~/.config/hypr/hyprland.conf`:

```
source = /etc/hypr/nvidia.conf
```

## Network Boot Installation

### Option 1: Network Boot with netboot.xyz

1. Set up a netboot.xyz server
2. Copy the `netboot/` files to your server
3. Update the `github_user` and `github_repo` variables in `netboot/boot.cfg`
4. Boot your machine via PXE and select the custom menu

### Option 2: Manual URL Installation

```bash
archinstall --config "https://raw.githubusercontent.com/danielbodnar/archconfigs/main/archinstall/user_configuration.json" \
            --creds "https://raw.githubusercontent.com/danielbodnar/archconfigs/main/archinstall/user_credentials.json"
```

## Configuration Details

### user_configuration.json

The main archinstall configuration includes:
- **Hostname**: `xps`
- **Kernels**: `linux`, `linux-zen`
- **Bootloader**: Systemd-boot
- **Disk**: Manual ZFS partitioning
- **Desktop**: Hyprland with sddm greeter
- **Graphics**: All open-source drivers
- **Custom repos**: archzfs for ZFS packages

### Packages

The configuration installs a curated set of packages including:
- **ZFS**: zfs-linux, zfs-linux-zen, zfs-utils
- **Terminal**: ghostty, alacritty, nushell
- **Editor**: neovim, neovide, zed
- **Rust tools**: cargo-*, rustup
- **Containers**: podman, podman-compose, podman-desktop
- **Fonts**: nerd-fonts, ttf-firacode-nerd, ttf-hack-nerd

### Dotfiles

System configuration files extracted for easy deployment:

| File | Purpose |
|------|---------|
| `dotfiles/hypr/nvidia.conf` | Hyprland NVIDIA environment variables |
| `dotfiles/etc/modprobe.d/nvidia.conf` | NVIDIA kernel module options |
| `dotfiles/etc/modprobe.d/audio.conf` | Intel HDA audio fixes |
| `dotfiles/etc/X11/xorg.conf.d/30-touchpad.conf` | XWayland touchpad config |
| `dotfiles/etc/udev/rules.d/80-nvidia-pm.rules` | NVIDIA power management |
| `dotfiles/etc/udev/rules.d/99-i2c-touchpad.rules` | Touchpad power fixes |

### user_credentials.json

Contains user account information for automated installation.

**⚠️ Important for Automated Installation**: The netboot automated installation requires valid password hashes. Using `null` will cause the installation to hang waiting for input.

**Generating password hashes:**

```bash
# Generate a yescrypt hash (recommended for archinstall)
mkpasswd -m yescrypt 'your-password-here'

# Or using openssl
openssl passwd -6 'your-password-here'
```

Replace the example hashes in `user_credentials.json` with your generated hashes:

```json
{
  "!root-password": "$y$j9T$YOUR_GENERATED_HASH_HERE$...",
  "!users": [
    {
      "!password": "$y$j9T$YOUR_GENERATED_HASH_HERE$...",
      "sudo": true,
      "username": "daniel"
    }
  ]
}
```

**Security Note**: Never commit real password hashes to public repositories. For private repos or local use, generate fresh hashes before installation.

## Validation

```bash
chmod +x scripts/*.sh
./scripts/validate-configs.sh
```

## Hardware Specifics

### Dell XPS 15 9500
- **CPU**: Intel Core i7-10750H
- **GPU**: NVIDIA GTX 1650 Ti + Intel UHD 630
- **Wi-Fi**: Killer Wi-Fi 6 AX1650
- **Touchpad**: ELAN (requires firmware updates)

### Known Issues
- Fingerprint reader not supported on Linux
- Deep sleep (S3) may have issues - s2idle recommended
- Touchpad may be laggy without firmware update (`update-touchpad-firmware`)

## Resources

- [Archinstall Documentation](https://wiki.archlinux.org/title/Archinstall)
- [ZFS on Arch Linux](https://wiki.archlinux.org/title/ZFS)
- [Hyprland Wiki](https://wiki.hyprland.org/)
- [netboot.xyz Documentation](https://netboot.xyz/docs/)

## License

MIT License - See LICENSE file for details