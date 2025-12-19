# PowerShell Core Upstall Scripts

[![ci](https://github.com/jonlabelle/pwsh-upstall/actions/workflows/ci.yml/badge.svg)](https://github.com/jonlabelle/pwsh-upstall/actions/workflows/ci.yml)

Platform-specific scripts to install/update PowerShell Core from GitHub releases with SHA256 verification.

- **macOS**: `upstall-pwsh-macos.sh` — Apple Silicon & Intel
- **Linux**: `upstall-pwsh-linux.sh` — x64/arm64, glibc/musl (Alpine)
- **Windows**: `upstall-pwsh-windows.ps1` — x64/arm64

<details>
<summary>Requirements & Security Features</summary>

**Requirements**: `curl`, internet access, 500MB+ disk space, sudo/admin privileges.

**Security**: SHA256 verification, signature validation (macOS), network pre-checks, disk space validation.

</details>

## Usage

### macOS

```bash
./upstall-pwsh-macos.sh                 # Install/update latest
./upstall-pwsh-macos.sh --tag v7.5.4   # Specific version
./upstall-pwsh-macos.sh --uninstall    # Remove
```

<details>
<summary>Options & Notes</summary>

Options: `--tag`, `--out-dir`, `--keep-pkg`, `--force`, `--uninstall`, `--skip-checksum`, `-n|--dry-run`, `-h|--help`

The Homebrew `powershell` cask is [deprecated](https://formulae.brew.sh/cask/powershell).

</details>

### Linux

```bash
./upstall-pwsh-linux.sh                 # Install/update latest
./upstall-pwsh-linux.sh --tag v7.5.4   # Specific version
./upstall-pwsh-linux.sh --uninstall    # Remove
```

<details>
<summary>Options & Notes</summary>

Options: `--tag`, `--out-dir`, `--keep-tar`, `--force`, `--uninstall`, `--skip-checksum`, `-n|--dry-run`, `-h|--help`

Detects x64/arm64 and glibc/musl. Installs to `/usr/local/microsoft/powershell/<version>` with symlink at `/usr/local/bin/pwsh`. Works with POSIX sh (including Alpine).

</details>

### Windows

⚠️ **Run from Windows PowerShell (`powershell.exe`), not PowerShell Core (`pwsh.exe`), to avoid process-in-use errors.**

```powershell
powershell -File .\upstall-pwsh-windows.ps1              # Install/update latest
powershell -File .\upstall-pwsh-windows.ps1 -Tag v7.5.4 # Specific version
powershell -File .\upstall-pwsh-windows.ps1 -Uninstall  # Remove
```

<details>
<summary>Options & Notes</summary>

Options: `-Tag`, `-OutDir`, `-KeepInstaller`, `-Force`, `-Uninstall`, `-SkipChecksum`, `-WhatIf`

Detects x64/arm64. Requires elevated session. Installs to `Program Files\PowerShell\7`.
</details>

<details>
<summary>Troubleshooting</summary>

**Checksum failed**: File corrupted or tampered. Retry or use `--skip-checksum`.

**Network error**: Check internet connection and firewall settings.

**Insufficient disk space**: Requires 500MB minimum free space.

**Permission denied**: Run with sudo (Linux/macOS) or as Administrator (Windows).

**Process in use (Windows)**: Exit `pwsh.exe` and run from `powershell.exe` instead.
</details>

## License

[MIT](LICENSE)
