# PowerShell Core Upstall Scripts

[![ci](https://github.com/jonlabelle/pwsh-upstall/actions/workflows/ci.yml/badge.svg)](https://github.com/jonlabelle/pwsh-upstall/actions/workflows/ci.yml)

Platform-specific scripts to install/update PowerShell Core from GitHub releases with SHA256 verification.

- **macOS**: `upstall-pwsh-macos.sh` — Apple Silicon & Intel
- **Linux**: `upstall-pwsh-linux.sh` — x64/arm64, glibc/musl (Alpine)
- **Windows**: `upstall-pwsh-windows.ps1` — x64/arm64

## Usage

### macOS & Linux

Downloads and installs PowerShell from GitHub releases with SHA256 verification. Auto-detects architecture and libc implementation.

```bash
# macOS one-liner install:
curl -fsSL https://raw.githubusercontent.com/jonlabelle/pwsh-upstall/refs/heads/main/upstall-pwsh-macos.sh | bash

# Linux one-liner install:
curl -fsSL https://raw.githubusercontent.com/jonlabelle/pwsh-upstall/refs/heads/main/upstall-pwsh-linux.sh | sh
```

```bash
# Install/update latest
./upstall-pwsh-macos.sh  # macOS
./upstall-pwsh-linux.sh  # Linux

# Specific version
./upstall-pwsh-macos.sh --tag v7.5.4  # macOS
./upstall-pwsh-linux.sh --tag v7.5.4  # Linux

# Remove
./upstall-pwsh-macos.sh --uninstall  # macOS
./upstall-pwsh-linux.sh --uninstall  # Linux
```

<details>
<summary>Options</summary>

| Option            | Description                                     |
| ----------------- | ----------------------------------------------- |
| `--tag <tag>`     | Install specific release version (e.g., v7.5.4) |
| `--out-dir <dir>` | Save downloaded package to specified directory  |
| `--keep`          | Keep the package file after installation        |
| `--force`         | Reinstall even if version already installed     |
| `--uninstall`     | Remove PowerShell installation                  |
| `--skip-checksum` | Skip SHA256 verification (not recommended)      |
| `-n, --dry-run`   | Show what would happen without executing        |
| `-h, --help`      | Display help message                            |

**macOS**: The Homebrew `powershell` cask is [deprecated](https://formulae.brew.sh/cask/powershell).

**Linux**: Detects x64/arm64 and glibc/musl. Installs to `/usr/local/microsoft/powershell/<version>` with symlink at `/usr/local/bin/pwsh`. Works with POSIX sh (including Alpine).

</details>

---

### Windows

Downloads and installs PowerShell from GitHub releases with SHA256 verification. Requires **elevated privileges**.

> [!Important]
> Run from Windows PowerShell (`powershell.exe`), not PowerShell Core (`pwsh.exe`), to avoid process-in-use errors.

```powershell
# Windows one-liner install:
irm 'https://raw.githubusercontent.com/jonlabelle/pwsh-upstall/refs/heads/main/upstall-pwsh-windows.ps1' |
    powershell -NoProfile -ExecutionPolicy Bypass -
```

```powershell
# Install/update latest
powershell -File .\upstall-pwsh-windows.ps1

# Specific version
powershell -File .\upstall-pwsh-windows.ps1 -Tag v7.5.4

# Remove
powershell -File .\upstall-pwsh-windows.ps1 -Uninstall
```

<details>
<summary>Options</summary>

| Option           | Description                                      |
| ---------------- | ------------------------------------------------ |
| `-Tag <tag>`     | Install specific release version (e.g., v7.5.4)  |
| `-OutDir <path>` | Save downloaded installer to specified directory |
| `-Keep`          | Keep the .msi file after installation            |
| `-Force`         | Reinstall even if version already installed      |
| `-Uninstall`     | Remove PowerShell installation                   |
| `-SkipChecksum`  | Skip SHA256 verification (not recommended)       |
| `-WhatIf`        | Show what would happen without executing         |

Detects x64/arm64. Requires elevated session. Installs to `Program Files\PowerShell\7`.

</details>

---

<details>
<summary>Troubleshooting</summary>

- **Checksum failed**: File corrupted or tampered. Retry or use `--skip-checksum`.

- **Network error**: Check internet connection and firewall settings.

- **Insufficient disk space**: Requires 500MB minimum free space.

- **Permission denied**: Run with sudo (Linux/macOS) or as Administrator (Windows).

- **Process in use (Windows)**: Exit `pwsh.exe` and run from `powershell.exe` instead.

</details>

## License

[MIT](LICENSE)
