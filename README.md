# archconfigs

Arch Linux automated installation configurations with netboot.xyz integration.

## Overview

This repository provides:
- **archinstall configurations**: JSON configuration files for automated Arch Linux installations
- **netboot.xyz integration**: Custom iPXE menus for network booting Arch Linux

## Directory Structure

```
├── archinstall/                    # Archinstall configuration files
│   ├── user_configuration.json     # System configuration (packages, locale, etc.)
│   ├── user_credentials.json       # User accounts and passwords
│   └── user_disk_layout.json       # Disk partitioning layout
├── netboot/                        # Netboot.xyz files
│   ├── custom.ipxe                 # Custom iPXE menu for Arch Linux
│   └── boot.cfg                    # Boot configuration
├── scripts/                        # Helper scripts
│   ├── validate-configs.sh         # Validate JSON configuration files
│   └── generate-config-url.sh      # Generate URLs for archinstall
└── README.md
```

## Quick Start

### Option 1: Network Boot with netboot.xyz

1. Set up a netboot.xyz server (see [netboot.xyz documentation](https://netboot.xyz/docs/selfhosting/))
2. Copy the `netboot/` files to your server
3. Update the `github_user` and `github_repo` variables in `netboot/boot.cfg`
4. Boot your machine via PXE and select the custom menu

### Option 2: Manual Installation

1. Boot into the Arch Linux ISO
2. Run archinstall with the configuration URLs:

```bash
# Set your GitHub username and repo
GITHUB_USER="your-username"
GITHUB_REPO="archconfigs"

archinstall --config "https://raw.githubusercontent.com/${GITHUB_USER}/${GITHUB_REPO}/main/archinstall/user_configuration.json" \
            --creds "https://raw.githubusercontent.com/${GITHUB_USER}/${GITHUB_REPO}/main/archinstall/user_credentials.json" \
            --disk_layouts "https://raw.githubusercontent.com/${GITHUB_USER}/${GITHUB_REPO}/main/archinstall/user_disk_layout.json"
```

## Configuration

### Archinstall Configuration Files

#### user_configuration.json

Contains the main system configuration:
- Hostname
- Locale settings
- Package selection
- Bootloader
- Audio configuration
- Network configuration
- Profile (desktop environment, etc.)

#### user_credentials.json

Contains user account information:
- Root password
- User accounts with passwords and sudo privileges

**Note**: For security, consider using password hashes or environment variables instead of plaintext passwords.

#### user_disk_layout.json

Defines the disk partitioning scheme. The default configuration uses automatic partitioning.

### Customization

1. Fork this repository
2. Edit the JSON files in `archinstall/` to match your requirements
3. Update the URLs in `netboot/custom.ipxe` and `netboot/boot.cfg`
4. Commit and push your changes

## Validation

Validate your configuration files:

```bash
./scripts/validate-configs.sh
```

Generate configuration URLs:

```bash
GITHUB_USER="your-username" GITHUB_REPO="archconfigs" ./scripts/generate-config-url.sh
```

## Security Considerations

- **Never commit plaintext passwords** to public repositories
- Use password hashes where possible
- Consider using private repositories for sensitive configurations
- The `user_credentials.json` file contains sensitive data - handle with care

## Resources

- [Archinstall Documentation](https://wiki.archlinux.org/title/Archinstall)
- [Archinstall GitHub](https://github.com/archlinux/archinstall)
- [netboot.xyz Documentation](https://netboot.xyz/docs/)
- [iPXE Documentation](https://ipxe.org/docs)

## License

MIT License - See LICENSE file for details