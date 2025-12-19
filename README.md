# PowerShell Upstall (macOS / Linux / Windows)

This repo provides platform-specific upstall scripts:

- `upstall-pwsh-macos.sh` (Bash): macOS installer/updater for Apple Silicon and Intel using the official `.pkg`.
- `upstall-pwsh-linux.sh` (POSIX sh): Linux installer/updater using release tarballs; detects glibc vs musl (Alpine) and `x64`/`arm64`.
- `upstall-pwsh-windows.ps1` (PowerShell): Windows installer/updater using the official MSI; works from PowerShell 5.1 or 7+.

## Requirements

- Common: `curl`, internet access to GitHub Releases.
- macOS: macOS 13+, `pkgutil`, `installer`, `python3` (or `python`), sudo access.
- Linux: `/bin/sh`, `curl`, `tar`, `python3` (or `python`), sudo/root. Works with glibc and musl-based distros (including Alpine) on `x86_64` and `arm64`.
- Windows: PowerShell 5.1+ or 7+, `msiexec`. Run from an elevated session for install/upgrade.

## macOS

> The Homebrew `powershell` cask is [deprecated](https://formulae.brew.sh/cask/powershell), and you can use this script instead.

```bash
./upstall-pwsh-macos.sh [options]
```

Options: `--tag <tag>`, `--out-dir <dir>`, `--keep-pkg`, `--force`, `--uninstall`, `-n|--dry-run`, `-h|--help`.

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

Options: `--tag <tag>`, `--out-dir <dir>`, `--keep-tar`, `--force`, `--uninstall`, `-n|--dry-run`, `-h|--help`.

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
pwsh -File .\upstall-pwsh-windows.ps1 [-Tag v7.5.4] [-OutDir <path>] [-KeepInstaller] [-Force] [-Uninstall] [-WhatIf]
```

Notes:

- Detects `x64` vs `arm64` and picks the matching `win-<arch>.msi`.
- Run from an elevated PowerShell session (7+ or Windows PowerShell 5.1). The MSI supports in-place upgrades even when launched from PowerShell 7; you do not need to switch to Windows PowerShell 5.1, though the installer may prompt you to close running `pwsh` instances.
- `-Uninstall` uses the MSI uninstall entry discovered in the registry; run elevated.
- Default install location is the standard MSI path under `Program Files\PowerShell\7`.

Examples:

```powershell
pwsh -File .\upstall-pwsh-windows.ps1
pwsh -File .\upstall-pwsh-windows.ps1 -Tag v7.5.4
pwsh -File .\upstall-pwsh-windows.ps1 -Uninstall
```

## What the scripts do

- Query the PowerShell GitHub Releases API (latest or specific tag).
- Auto-select the correct asset for your platform/arch:
  - macOS: `osx-arm64.pkg` or `osx-x64.pkg`
  - Linux: `linux-<arch>.tar.gz` or `linux-musl-<arch>.tar.gz`
  - Windows: `win-<arch>.msi`
- Download, install/upgrade, and skip reinstalling if the target version is already present unless forced.
- macOS/Linux: optional uninstall removes the install directory and the `pwsh` symlink.
- Post-install, verifies `pwsh` availability (macOS/Linux) or prints a completion message (Windows).

## License

[MIT](LICENSE)
