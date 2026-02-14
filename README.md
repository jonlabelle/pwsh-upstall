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

Use the command for your platform:

| Platform | Command                                       |
| -------- | --------------------------------------------- |
| macOS    | `./upstall-pwsh-macos.sh`                     |
| Linux    | `./upstall-pwsh-linux.sh`                     |
| Windows  | `powershell -File .\upstall-pwsh-windows.ps1` |

> [!Note]
> On Windows, run from Windows PowerShell (`powershell.exe`), not PowerShell Core (`pwsh.exe`).

### Common actions

| Action                           | macOS                                 | Linux                                 | Windows                                                  |
| -------------------------------- | ------------------------------------- | ------------------------------------- | -------------------------------------------------------- |
| Install/update latest stable     | `./upstall-pwsh-macos.sh`             | `./upstall-pwsh-linux.sh`             | `powershell -File .\upstall-pwsh-windows.ps1`            |
| Check if up to date (no install) | `./upstall-pwsh-macos.sh --check`     | `./upstall-pwsh-linux.sh --check`     | `powershell -File .\upstall-pwsh-windows.ps1 -Check`     |
| Uninstall                        | `./upstall-pwsh-macos.sh --uninstall` | `./upstall-pwsh-linux.sh --uninstall` | `powershell -File .\upstall-pwsh-windows.ps1 -Uninstall` |

### Select a version (`--tag` / `-Tag`)

Use semver selectors to choose a release:

```text
v7      -> latest 7.x release
v7.5    -> latest 7.5.x release
v7.5.4  -> specific patch release
```

Examples:

```bash
./upstall-pwsh-macos.sh --tag v7
./upstall-pwsh-linux.sh --tag v7.5
```

```powershell
powershell -File .\upstall-pwsh-windows.ps1 -Tag v7.5.4
```

> [!Note]
> Prereleases require an explicit exact tag (for example, `v7.6.0-preview.1`). Default/latest/major/minor selection is stable-only.

### Option mapping

| Purpose                             | macOS/Linux       | Windows          |
| ----------------------------------- | ----------------- | ---------------- |
| Select version                      | `--tag <tag>`     | `-Tag <tag>`     |
| Save downloaded package/installer   | `--out-dir <dir>` | `-OutDir <path>` |
| Keep downloaded package/installer   | `--keep`          | `-Keep`          |
| Reinstall even if already installed | `--force`         | `-Force`         |
| Check only (no install)             | `--check`         | `-Check`         |
| Uninstall                           | `--uninstall`     | `-Uninstall`     |
| Skip SHA256 verification            | `--skip-checksum` | `-SkipChecksum`  |
| Dry run                             | `-n, --dry-run`   | `-WhatIf`        |
| Help                                | `-h, --help`      | N/A              |

> [!Note]
> **Windows** automatically detects x64/arm64 architecture, requires Administrator privileges, and installs to `Program Files\PowerShell\7`.

## Troubleshooting

- **Checksum failed**: File corrupted or tampered. Retry or use `--skip-checksum`.
- **Insufficient disk space**: Requires 500MB minimum free space.
- **Permission denied**: Run with sudo (Linux/macOS) or as Administrator (Windows).
- **Process in use (Windows)**: Exit `pwsh.exe` and run from `powershell.exe` instead.

## License

[MIT](LICENSE)
