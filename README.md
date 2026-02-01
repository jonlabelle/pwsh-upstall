# PowerShell Core Upstall Scripts

[![ci](https://github.com/jonlabelle/pwsh-upstall/actions/workflows/ci.yml/badge.svg)](https://github.com/jonlabelle/pwsh-upstall/actions/workflows/ci.yml)

Platform-specific scripts to install/update PowerShell Core from GitHub releases with SHA256 verification.

- **macOS**: `upstall-pwsh-macos.sh` — Apple Silicon & Intel
- **Linux**: `upstall-pwsh-linux.sh` — x64/arm64, glibc/musl (Alpine)
- **Windows**: `upstall-pwsh-windows.ps1` — x64/arm64

## Table of contents

- [Install](#install)
  - [One-liners](#one-liners)
  - [Other options](#other-options)
- [Run locally](#run-locally)
  - [macOS & Linux](#macos--linux)
  - [Windows](#windows-1)
- [Troubleshooting](#troubleshooting)
- [License](#license)

## Install

### One-liners

#### macOS

```bash
curl -fsSL https://raw.githubusercontent.com/jonlabelle/pwsh-upstall/refs/heads/main/upstall-pwsh-macos.sh | bash
```

#### Linux

```bash
curl -fsSL https://raw.githubusercontent.com/jonlabelle/pwsh-upstall/refs/heads/main/upstall-pwsh-linux.sh | sh
```

#### Windows

```powershell
# Requires elevated privileges
irm 'https://raw.githubusercontent.com/jonlabelle/pwsh-upstall/refs/heads/main/upstall-pwsh-windows.ps1' |
    powershell -NoProfile -ExecutionPolicy Bypass -
```

> [!Note]
> Run from Windows PowerShell (`powershell.exe`), not PowerShell Core (`pwsh.exe`), to avoid process-in-use errors.

---

### Other options

#### Clone the repo

```bash
git clone https://github.com/jonlabelle/pwsh-upstall.git
cd pwsh-upstall
```

#### Download the archive (macOS/Linux)

```bash
curl -L -o pwsh-upstall.zip https://github.com/jonlabelle/pwsh-upstall/archive/refs/heads/main.zip
unzip pwsh-upstall.zip
cd pwsh-upstall-main
```

#### Download the archive (Windows)

```powershell
Invoke-WebRequest -Uri https://github.com/jonlabelle/pwsh-upstall/archive/refs/heads/main.zip -OutFile pwsh-upstall.zip
Expand-Archive -Path pwsh-upstall.zip -DestinationPath .
Set-Location .\pwsh-upstall-main
```

## Run locally

### macOS & Linux

> Replace `<platform>` with `macos` or `linux` accordingly.

#### Install/update latest

```bash
./upstall-pwsh-<platform>.sh
```

#### Check if PowerShell is up to date

```bash
./upstall-pwsh-<platform>.sh --check
```

#### Specific version

```bash
./upstall-pwsh-<platform>.sh --tag v7.5.4
```

#### Remove

```bash
./upstall-pwsh-<platform>.sh --uninstall
```

#### macOS/Linux options

| Option            | Description                                     |
| ----------------- | ----------------------------------------------- |
| `--tag <tag>`     | Install specific release version (e.g., v7.5.4) |
| `--out-dir <dir>` | Save downloaded package to specified directory  |
| `--keep`          | Keep the package file after installation        |
| `--force`         | Reinstall even if version already installed     |
| `--check`         | Only check if installed version is up to date   |
| `--uninstall`     | Remove PowerShell installation                  |
| `--skip-checksum` | Skip SHA256 verification (not recommended)      |
| `-n, --dry-run`   | Show what would happen without executing        |
| `-h, --help`      | Display help message                            |

---

### Windows

#### Install/update latest

```powershell
powershell -File .\upstall-pwsh-windows.ps1
```

#### Check if PowerShell is up to date

```powershell
powershell -File .\upstall-pwsh-windows.ps1 -Check
```

#### Specific version

```powershell
powershell -File .\upstall-pwsh-windows.ps1 -Tag v7.5.4
```

#### Remove

```powershell
powershell -File .\upstall-pwsh-windows.ps1 -Uninstall
```

#### Windows options

| Option           | Description                                      |
| ---------------- | ------------------------------------------------ |
| `-Tag <tag>`     | Install specific release version (e.g., v7.5.4)  |
| `-OutDir <path>` | Save downloaded installer to specified directory |
| `-Keep`          | Keep the .msi file after installation            |
| `-Force`         | Reinstall even if version already installed      |
| `-Check`         | Only check if installed version is up to date    |
| `-Uninstall`     | Remove PowerShell installation                   |
| `-SkipChecksum`  | Skip SHA256 verification (not recommended)       |
| `-WhatIf`        | Show what would happen without executing         |

Detects x64/arm64. Requires elevated session. Installs to `Program Files\PowerShell\7`.

## Troubleshooting

- **Checksum failed**: File corrupted or tampered. Retry or use `--skip-checksum`.

- **Network error**: Check internet connection and firewall settings.

- **Insufficient disk space**: Requires 500MB minimum free space.

- **Permission denied**: Run with sudo (Linux/macOS) or as Administrator (Windows).

- **Process in use (Windows)**: Exit `pwsh.exe` and run from `powershell.exe` instead.

## License

[MIT](LICENSE)
