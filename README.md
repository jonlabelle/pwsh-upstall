# PowerShell Installer for macOS

> The Homebrew `powershell` cask is [deprecated](https://formulae.brew.sh/cask/powershell). This script installs PowerShell on macOS, automatically selecting the correct Apple Silicon (arm64) or Intel (x64) package from the official GitHub Releases.

This script downloads and installs **Microsoft PowerShell** on **macOS**, detecting your architecture and pulling the matching installer directly from the [official GitHub Releases](https://github.com/powershell/powershell/releases).

## Requirements

- macOS 13+ (tested on macOS Tahoe 26.1)
- Apple Silicon (`arm64`) or Intel (`x86_64`)
- `curl`
- `pkgutil`
- `installer`
- `python3` (or `python`)
- `sudo` access (for installation/uninstall)

## Usage

```bash
./upstall-pwsh-macos.sh [options]
```

If the target version is already installed, the script exits without reinstalling unless `--force` is used.
Use `--uninstall` to remove the default PowerShell install created by this script.

### Options

| Option            | Description                                               |
| ----------------- | --------------------------------------------------------- |
| `--tag <tag>`     | Install a specific GitHub release tag (e.g. `v7.5.4`)     |
| `--out-dir <dir>` | Directory to save the downloaded `.pkg`                   |
| `--keep-pkg`      | Keep the downloaded `.pkg` after installation             |
| `--force`         | Reinstall even if the target version is already installed |
| `--uninstall`     | Uninstall PowerShell from the default install location    |
| `-n`, `--dry-run` | Show what would happen without downloading or installing  |
| `-h`, `--help`    | Show help                                                 |

## Examples

### Install the latest stable PowerShell

```bash
./upstall-pwsh-macos.sh
```

### Install a specific version

```bash
./upstall-pwsh-macos.sh --tag v7.5.4
```

### Reinstall even if already on the target version

```bash
./upstall-pwsh-macos.sh --force
```

### Uninstall PowerShell

```bash
./upstall-pwsh-macos.sh --uninstall
```

### Preview actions only (no download, no sudo)

```bash
./upstall-pwsh-macos.sh --dry-run
```

### Download to `~/Downloads` and keep the package

```bash
./upstall-pwsh-macos.sh --out-dir "$HOME/Downloads" --keep-pkg
```

## What the script does

1. Queries the PowerShell GitHub Releases API
2. Detects your architecture and selects the official `osx-arm64.pkg` or `osx-x64.pkg`
3. Downloads the package
4. Verifies the installer signature:
5. Installs PowerShell using `sudo installer -pkg <pkg> -target /`
6. Verifies `pwsh` is available and prints the version

> With `--uninstall`, it removes `/usr/local/microsoft/powershell` and the `/usr/local/bin/pwsh` symlink, and forgets any PowerShell package receipts it finds.

## Install location

PowerShell is installed to:

```plaintext
/usr/local/microsoft/powershell/7/
```

The `pwsh` binary is symlinked into:

```plaintext
/usr/local/bin/pwsh
```

## License

[MIT](LICENSE)
