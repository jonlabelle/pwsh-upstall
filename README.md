# PowerShell Core Upstall Scripts

[![ci](https://github.com/jonlabelle/pwsh-upstall/actions/workflows/ci.yml/badge.svg)](https://github.com/jonlabelle/pwsh-upstall/actions/workflows/ci.yml)

Platform-specific scripts to install/update PowerShell Core from GitHub releases with SHA256 verification.

- **macOS**: `upstall-pwsh-macos.sh` — Apple Silicon & Intel
- **Linux**: `upstall-pwsh-linux.sh` — x64/arm64, glibc/musl (Alpine)
- **Windows**: `upstall-pwsh-windows.ps1` — x64/arm64

![Checks if PowerShell is up to date](screenshot.png "Checks if PowerShell is up to date")

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

The default behavior is to install/update to the latest stable release. To specify a different version, use the `--tag` option (see below).

```bash
./upstall-pwsh-<platform>.sh
```

#### Check if PowerShell is up to date

Check if the installed PowerShell version is up to date without performing an installation:

```bash
./upstall-pwsh-<platform>.sh --check
```

#### Semver selector (major/minor/patch)

Specify a semver selector to choose the desired release:

```bash
# Latest 7.x release (major track)
./upstall-pwsh-<platform>.sh --tag v7

# Latest 7.5.x release (minor track)
./upstall-pwsh-<platform>.sh --tag v7.5

# Specific patch release
./upstall-pwsh-<platform>.sh --tag v7.5.4
```

> [!Note]
> Prereleases are supported only by explicit exact tag; default/latest/major/minor selection is stable-only.

#### Uninstall

```bash
./upstall-pwsh-<platform>.sh --uninstall
```

#### macOS/Linux options

| Option            | Description                                                                                        |
| ----------------- | -------------------------------------------------------------------------------------------------- |
| `--tag <tag>`     | Semver selector: `v7` (latest 7.x), `v7.5` (latest 7.5.x), `v7.5.4` (specific patch), or exact tag |
| `--out-dir <dir>` | Save downloaded package to specified directory                                                     |
| `--keep`          | Keep the package file after installation                                                           |
| `--force`         | Reinstall even if version already installed                                                        |
| `--check`         | Only check if installed version is up to date                                                      |
| `--uninstall`     | Remove PowerShell installation                                                                     |
| `--skip-checksum` | Skip SHA256 verification (not recommended)                                                         |
| `-n, --dry-run`   | Show what would happen without executing                                                           |
| `-h, --help`      | Display help message                                                                               |

> Prereleases require explicit exact tag, e.g. `--tag v7.6.0-preview.1`.

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

#### Semver selector (major/minor/patch)

Specify a semver selector to choose the desired release:

```powershell
# Latest 7.x release (major track)
powershell -File .\upstall-pwsh-windows.ps1 -Tag v7

# Latest 7.5.x release (minor track)
powershell -File .\upstall-pwsh-windows.ps1 -Tag v7.5

# Specific patch release
powershell -File .\upstall-pwsh-windows.ps1 -Tag v7.5.4
```

Prereleases are supported only by explicit exact tag; default/latest/major/minor selection is stable-only.

#### Uninstall

```powershell
powershell -File .\upstall-pwsh-windows.ps1 -Uninstall
```

#### Windows options

| Option           | Description                                                                                                                                |
| ---------------- | ------------------------------------------------------------------------------------------------------------------------------------------ |
| `-Tag <tag>`     | Semver selector: `v7` (latest 7.x), `v7.5` (latest 7.5.x), `v7.5.4` (specific patch), or exact tag; prereleases require explicit exact tag |
| `-OutDir <path>` | Save downloaded installer to specified directory                                                                                           |
| `-Keep`          | Keep the .msi file after installation                                                                                                      |
| `-Force`         | Reinstall even if version already installed                                                                                                |
| `-Check`         | Only check if installed version is up to date                                                                                              |
| `-Uninstall`     | Remove PowerShell installation                                                                                                             |
| `-SkipChecksum`  | Skip SHA256 verification (not recommended)                                                                                                 |
| `-WhatIf`        | Show what would happen without executing                                                                                                   |

Detects x64/arm64. Requires elevated session. Installs to `Program Files\PowerShell\7`.

## Troubleshooting

- **Checksum failed**: File corrupted or tampered. Retry or use `--skip-checksum`.

- **Network error**: Check internet connection and firewall settings.

- **Insufficient disk space**: Requires 500MB minimum free space.

- **Permission denied**: Run with sudo (Linux/macOS) or as Administrator (Windows).

- **Process in use (Windows)**: Exit `pwsh.exe` and run from `powershell.exe` instead.

## License

[MIT](LICENSE)
