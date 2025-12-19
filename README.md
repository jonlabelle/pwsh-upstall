# PowerShell Core Upstall Scripts

[![ci](https://github.com/jonlabelle/pwsh-upstall/actions/workflows/ci.yml/badge.svg)](https://github.com/jonlabelle/pwsh-upstall/actions/workflows/ci.yml)

Platform-specific scripts to install/update PowerShell Core from GitHub releases with SHA256 verification.

- **macOS**: `upstall-pwsh-macos.sh` — Apple Silicon & Intel
- **Linux**: `upstall-pwsh-linux.sh` — x64/arm64, glibc/musl (Alpine)
- **Windows**: `upstall-pwsh-windows.ps1` — x64/arm64

## Usage

### macOS

```bash
# Install/update latest
./upstall-pwsh-macos.sh

# Specific version
./upstall-pwsh-macos.sh --tag v7.5.4

# Remove
./upstall-pwsh-macos.sh --uninstall
```

<details>
<summary>Options</summary>

| Option            | Description                                     |
| ----------------- | ----------------------------------------------- |
| `--tag <tag>`     | Install specific release version (e.g., v7.5.4) |
| `--out-dir <dir>` | Save downloaded package to specified directory  |
| `--keep-pkg`      | Keep the .pkg file after installation           |
| `--force`         | Reinstall even if version already installed     |
| `--uninstall`     | Remove PowerShell installation                  |
| `--skip-checksum` | Skip SHA256 verification (not recommended)      |
| `-n, --dry-run`   | Show what would happen without executing        |
| `-h, --help`      | Display help message                            |

The Homebrew `powershell` cask is [deprecated](https://formulae.brew.sh/cask/powershell).

</details>

---

### Linux

```bash
# Install/update latest
./upstall-pwsh-linux.sh

# Specific version
./upstall-pwsh-linux.sh --tag v7.5.4

# Remove
./upstall-pwsh-linux.sh --uninstall
```

<details>
<summary>Options</summary>

| Option            | Description                                     |
| ----------------- | ----------------------------------------------- |
| `--tag <tag>`     | Install specific release version (e.g., v7.5.4) |
| `--out-dir <dir>` | Save downloaded tarball to specified directory  |
| `--keep-tar`      | Keep the .tar.gz file after installation        |
| `--force`         | Reinstall even if version already installed     |
| `--uninstall`     | Remove PowerShell installation                  |
| `--skip-checksum` | Skip SHA256 verification (not recommended)      |
| `-n, --dry-run`   | Show what would happen without executing        |
| `-h, --help`      | Display help message                            |

Detects x64/arm64 and glibc/musl. Installs to `/usr/local/microsoft/powershell/<version>` with symlink at `/usr/local/bin/pwsh`. Works with POSIX sh (including Alpine).

</details>

---

### Windows

> [!Important]
> Run from Windows PowerShell (`powershell.exe`), not PowerShell Core (`pwsh.exe`), to avoid process-in-use errors.

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
| `-KeepInstaller` | Keep the .msi file after installation            |
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
