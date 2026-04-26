# PowerShell Core Upstall Scripts

[![ci](https://github.com/jonlabelle/pwsh-upstall/actions/workflows/ci.yml/badge.svg)](https://github.com/jonlabelle/pwsh-upstall/actions/workflows/ci.yml)

Install, update, check, or uninstall PowerShell Core on Windows, macOS, and Linux from official GitHub releases with SHA256 verification.

| Platform | Script                                                   | Supported Architectures        |
| -------- | -------------------------------------------------------- | ------------------------------ |
| Windows  | [`pwsh-upstall-windows.ps1`](./pwsh-upstall-windows.ps1) | x64/arm64                      |
| macOS    | [`pwsh-upstall-macos.sh`](./pwsh-upstall-macos.sh)       | Apple Silicon and Intel        |
| Linux    | [`pwsh-upstall-linux.sh`](./pwsh-upstall-linux.sh)       | x64/arm64, glibc/musl (Alpine) |

> Upgrades remove the previously active version by default. Use `--keep-old-version` or `-KeepOldVersion` to keep it.

![Checks if PowerShell is up to date](screenshot.png "Checks if PowerShell is up to date")

## Table of Contents

- [Quick Install](#quick-install)
  - [Windows](#windows)
  - [macOS](#macos)
  - [Linux](#linux)
- [Common Actions](#common-actions)
- [Options](#options)
- [Select a Version](#select-a-version)
- [Run with Options](#run-with-options)
  - [macOS/Linux](#macoslinux)
  - [Windows](#windows-1)
- [Run from a Local Copy](#run-from-a-local-copy)
  - [Clone with Git](#clone-with-git)
  - [Download the Archive](#download-the-archive)
- [Troubleshooting](#troubleshooting)
- [License](#license)

## Quick Install

These one-liners install or update to the latest stable release.

> You'll need to [download the script](#download-the-archive) first if you need [options](#options) like `--tag`, `--check`, or `-WhatIf`.

### Windows

> [!Important]
> Requires Administrator privileges. Run from an [elevated Windows PowerShell prompt](https://learn.microsoft.com/powershell/scripting/windows-powershell/starting-windows-powershell#run-with-administrative-privileges), not PowerShell Core (`pwsh.exe`), to avoid process-in-use errors.

```powershell
irm 'https://raw.githubusercontent.com/jonlabelle/pwsh-upstall/refs/heads/main/pwsh-upstall-windows.ps1' |
    powershell -NoProfile -ExecutionPolicy Bypass -
```

> [!Note]
> `powershell.exe -` runs the script from stdin and cannot pass script parameters. Use `powershell -File .\pwsh-upstall-windows.ps1 ...` when you need `-Tag`, `-Check`, `-WhatIf`, or [other options](#options).

### macOS

```bash
curl -fsSL https://raw.githubusercontent.com/jonlabelle/pwsh-upstall/refs/heads/main/pwsh-upstall-macos.sh | bash
```

### Linux

```bash
curl -fsSL https://raw.githubusercontent.com/jonlabelle/pwsh-upstall/refs/heads/main/pwsh-upstall-linux.sh | sh
```

## Common Actions

**Windows:**

| Action                           | Command                                                  |
| -------------------------------- | -------------------------------------------------------- |
| Install/update latest stable     | `powershell -File .\pwsh-upstall-windows.ps1`            |
| Check if up to date (no install) | `powershell -File .\pwsh-upstall-windows.ps1 -Check`     |
| Uninstall                        | `powershell -File .\pwsh-upstall-windows.ps1 -Uninstall` |

**macOS:**

| Action                           | Command                                    |
| -------------------------------- | ------------------------------------------ |
| Install/update latest stable     | `bash ./pwsh-upstall-macos.sh`             |
| Check if up to date (no install) | `bash ./pwsh-upstall-macos.sh --check`     |
| Uninstall                        | `bash ./pwsh-upstall-macos.sh --uninstall` |

**Linux:**

| Action                           | Command                                  |
| -------------------------------- | ---------------------------------------- |
| Install/update latest stable     | `sh ./pwsh-upstall-linux.sh`             |
| Check if up to date (no install) | `sh ./pwsh-upstall-linux.sh --check`     |
| Uninstall                        | `sh ./pwsh-upstall-linux.sh --uninstall` |

## Options

| Purpose                             | macOS/Linux          | Windows                               |
| ----------------------------------- | -------------------- | ------------------------------------- |
| Select version                      | `--tag <tag>`        | `-Tag <tag>`                          |
| Save downloaded package/installer   | `--out-dir <dir>`    | `-OutDir <path>`                      |
| Keep downloaded package/installer   | `--keep`             | `-Keep`                               |
| Reinstall even if already installed | `--force`            | `-Force`                              |
| Keep old version during upgrade     | `--keep-old-version` | `-KeepOldVersion`                     |
| Check only (no install)             | `--check`            | `-Check`                              |
| Uninstall                           | `--uninstall`        | `-Uninstall`                          |
| Skip SHA256 verification            | `--skip-checksum`    | `-SkipChecksum`                       |
| Dry run                             | `-n, --dry-run`      | `-WhatIf`                             |
| Help                                | `-h, --help`         | `Get-Help .\pwsh-upstall-windows.ps1` |

> [!Note]
> Windows automatically detects x64/arm64 architecture, requires Administrator privileges, and installs to `Program Files\PowerShell\7`.

## Select a Version

Use semver selectors to choose a release:

```text
v7      -> latest 7.x release
v7.6    -> latest 7.5.x release
v7.6.4  -> specific patch release
```

Examples:

```bash
bash ./pwsh-upstall-macos.sh --tag v7
sh ./pwsh-upstall-linux.sh --tag v7.6
```

```powershell
powershell -File .\pwsh-upstall-windows.ps1 -Tag v7.6.4
```

> [!Note]
> Prereleases require an exact tag, for example `v7.6.0-preview.1`. Default/latest/major/minor selection is stable-only.

## Run with Options

Download the script first when you need to pass options.

### Windows

```powershell
Invoke-WebRequest `
    -Uri https://raw.githubusercontent.com/jonlabelle/pwsh-upstall/refs/heads/main/pwsh-upstall-windows.ps1 `
    -OutFile pwsh-upstall-windows.ps1

powershell -File .\pwsh-upstall-windows.ps1 -Tag v7.6
```

### macOS/Linux

```bash
# macOS
curl -fsSLO https://raw.githubusercontent.com/jonlabelle/pwsh-upstall/refs/heads/main/pwsh-upstall-macos.sh
bash ./pwsh-upstall-macos.sh --tag v7.6

# Linux
curl -fsSLO https://raw.githubusercontent.com/jonlabelle/pwsh-upstall/refs/heads/main/pwsh-upstall-linux.sh
sh ./pwsh-upstall-linux.sh --tag v7.6
```

## Run from a Local Copy

### Clone with Git

```bash
git clone https://github.com/jonlabelle/pwsh-upstall.git
cd pwsh-upstall

# macOS
bash ./pwsh-upstall-macos.sh

# Linux
sh ./pwsh-upstall-linux.sh

# Windows (from PowerShell, requires Administrator privileges)
powershell -File .\pwsh-upstall-windows.ps1
```

### Download the Archive

**Windows:**

```powershell
Invoke-WebRequest -Uri https://github.com/jonlabelle/pwsh-upstall/archive/refs/heads/main.zip -OutFile pwsh-upstall.zip
Expand-Archive -Path pwsh-upstall.zip -DestinationPath .
Set-Location .\pwsh-upstall-main

# Requires Administrator privileges
powershell -File .\pwsh-upstall-windows.ps1
```

**macOS/Linux:**

```bash
curl -L -o pwsh-upstall.zip https://github.com/jonlabelle/pwsh-upstall/archive/refs/heads/main.zip
unzip pwsh-upstall.zip
cd pwsh-upstall-main

# macOS
bash ./pwsh-upstall-macos.sh

# Linux
sh ./pwsh-upstall-linux.sh
```

## Troubleshooting

- **Checksum failed**: Retry the download. Use `--skip-checksum` only if you trust the source and accept the risk.
- **Insufficient disk space**: Free at least 500 MB and rerun the script.
- **Permission denied**: Run with `sudo` on Linux/macOS or as Administrator on Windows.
- **Process in use (Windows)**: Exit `pwsh.exe` and run from `powershell.exe` instead.
- **Windows options with one-liners**: Download the script and run it with `powershell -File .\pwsh-upstall-windows.ps1 ...`.

## License

[MIT](LICENSE)
