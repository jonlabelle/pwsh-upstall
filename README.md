# PowerShell Upstall (macOS / Linux / Windows)

This repo provides platform-specific upstall scripts:

- `upstall-pwsh-macos.sh` (Bash): macOS installer/updater for Apple Silicon and Intel using the official `.pkg`.
- `upstall-pwsh-linux.sh` (POSIX sh): Linux installer/updater using release tarballs; detects glibc vs musl (Alpine) and `x64`/`arm64`.
- `upstall-pwsh-windows.ps1` (PowerShell): Windows installer/updater using the official MSI; works from PowerShell 5.1 or 7+.

## Requirements

- Common: `curl`, internet access to GitHub Releases, 500MB+ free disk space.
- macOS: macOS 13+, `pkgutil`, `installer`, `shasum`, `python3` (or `python`), sudo access.
- Linux: `/bin/sh`, `curl`, `tar`, `sha256sum`, `python3` (or `python`), sudo/root. Works with glibc and musl-based distros (including Alpine) on `x86_64` and `arm64`.
- Windows: PowerShell 5.1+ or 7+, `msiexec`. Run from an elevated session for install/upgrade.

## Security Features

- **SHA256 Verification**: Downloads and verifies SHA256 checksums from GitHub releases (can be disabled with `--skip-checksum` / `-SkipChecksum`).
- **Signature Validation**: macOS verifies Microsoft Corporation code signature on `.pkg` files.
- **Network Validation**: Pre-flight checks ensure GitHub API connectivity before downloads.
- **Partial Download Detection**: Automatically removes incomplete downloads before retrying.
- **Disk Space Checks**: Verifies sufficient disk space (500MB) before downloading.

## macOS

> The Homebrew `powershell` cask is [deprecated](https://formulae.brew.sh/cask/powershell), and you can use this script instead.

```bash
./upstall-pwsh-macos.sh [options]
```

Options: `--tag <tag>`, `--out-dir <dir>`, `--keep-pkg`, `--force`, `--uninstall`, `--skip-checksum`, `-n|--dry-run`, `-h|--help`.

Examples:

```bash
./upstall-pwsh-macos.sh
./upstall-pwsh-macos.sh --tag v7.5.4
./upstall-pwsh-macos.sh --force
./upstall-pwsh-macos.sh --uninstall
./upstall-pwsh-macos.sh --dry-run
```

## Linux

```bash
./upstall-pwsh-linux.sh [options]
```

Options: `--tag <tag>`, `--out-dir <dir>`, `--keep-tar`, `--force`, `--uninstall`, `--skip-checksum`, `-n|--dry-run`, `-h|--help`.

Examples:

```bash
./upstall-pwsh-linux.sh
./upstall-pwsh-linux.sh --tag v7.5.4
./upstall-pwsh-linux.sh --force
./upstall-pwsh-linux.sh --uninstall
./upstall-pwsh-linux.sh --dry-run
```

Notes:

- Detects `x64` vs `arm64` and glibc vs musl to pick `linux-<arch>.tar.gz` or `linux-musl-<arch>.tar.gz`.
- Installs to `/usr/local/microsoft/powershell/<version>` and symlinks `/usr/local/bin/pwsh`.
- No Bash required; works with `/bin/sh` (including Alpine's `ash`).

## Windows

```powershell
powershell -File .\upstall-pwsh-windows.ps1 [-Tag v7.5.4] [-OutDir <path>] [-KeepInstaller] [-Force] [-Uninstall] [-SkipChecksum] [-WhatIf]
```

**Important**: Run from Windows PowerShell (`powershell.exe`), not PowerShell Core (`pwsh.exe`), to avoid process-in-use errors during upgrades. If you run from `pwsh`, the MSI installer cannot update the running process.

Notes:

- Detects `x64` vs `arm64` and picks the matching `win-<arch>.msi`.
- Run from an elevated Windows PowerShell session (5.1). The script works from PowerShell 5.1 or 7+, but **for upgrades, use Windows PowerShell** to avoid locking issues.
- `-Uninstall` uses the MSI uninstall entry discovered in the registry; run elevated.
- Default install location is the standard MSI path under `Program Files\PowerShell\7`.

Examples:

```powershell
# Run from Windows PowerShell (not pwsh)
powershell -File .\upstall-pwsh-windows.ps1
powershell -File .\upstall-pwsh-windows.ps1 -Tag v7.5.4
powershell -File .\upstall-pwsh-windows.ps1 -Uninstall
```

## What the scripts do

- Validate network connectivity to GitHub before starting.
- Check available disk space (requires 500MB minimum).
- Query the PowerShell GitHub Releases API (latest or specific tag).
- Auto-select the correct asset for your platform/arch:
  - macOS: `osx-arm64.pkg` or `osx-x64.pkg`
  - Linux: `linux-<arch>.tar.gz` or `linux-musl-<arch>.tar.gz`
  - Windows: `win-<arch>.msi`
- Download installer/package with automatic retry on failure.
- Verify SHA256 checksum against published hashes from GitHub (unless `--skip-checksum` specified).
- Additional verification:
  - macOS: Verify Microsoft Corporation code signature
  - Windows: Validate MSI exit codes
- Install/upgrade with proper error handling and cleanup.
- Use semantic version comparison to skip reinstalls of same version (unless `--force`).
- macOS/Linux: optional uninstall removes the install directory and the `pwsh` symlink.
- Automatic cleanup of temporary files on both success and failure.
- Post-install verification of `pwsh` availability.

## Error Handling

All scripts include comprehensive error handling:

- Automatic cleanup of temporary files on failure
- Network connectivity validation before downloads
- Disk space verification before downloads begin
- SHA256 checksum verification (prevents corrupted/tampered downloads)
- Exit code validation for installers/uninstallers
- Partial download detection and cleanup

## Troubleshooting

**Checksum verification failed**: The downloaded file is corrupted or doesn't match the published hash. The script will exit with an error. Try running again, or use `--skip-checksum` to bypass (not recommended).

**Network connectivity error**: Cannot reach GitHub API. Check your internet connection and firewall settings.

**Insufficient disk space**: At least 500MB of free disk space is required. Free up space and try again.

**Permission denied (Linux/macOS)**: Installation requires sudo/root privileges. Run with `sudo` or as root.

**Elevation required (Windows)**: Run PowerShell as Administrator.

**Process in use error (Windows)**: If the MSI installer reports that PowerShell is in use, you're likely running the script from `pwsh.exe` (PowerShell Core). Exit and run from Windows PowerShell (`powershell.exe`) instead.

## License

[MIT](LICENSE)
