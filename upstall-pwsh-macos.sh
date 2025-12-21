#!/usr/bin/env bash
set -euo pipefail

# upstall-pwsh-macos.sh
#
# DESCRIPTION:
#   Bash script to install, upgrade, or uninstall Microsoft PowerShell on macOS
#   using official GitHub release packages. Supports both ARM64 (Apple Silicon) and
#   x86_64 (Intel) architectures.
#
# REQUIREMENTS:
#   - macOS 13.0 or later
#   - bash (system default)
#   - curl (for downloading releases)
#   - python3 or python (for JSON parsing and version comparison)
#   - sudo privileges (for installation/uninstall)
#   - pkgutil (for signature verification, system default)
#   - shasum (for checksum verification, can be skipped with --skip-checksum)
#
# USAGE:
#   ./upstall-pwsh-macos.sh [options]
#
#   Options:
#     --tag <tag>        Install specific GitHub release tag (e.g., v7.5.4)
#     --out-dir <dir>    Save downloaded package to specified directory
#     --keep             Retain package after installation
#     --force            Reinstall even if target version already installed
#     --uninstall        Remove PowerShell and associated package receipts
#     --skip-checksum    Skip SHA256 verification (not recommended)
#     -n, --dry-run      Preview actions without making changes
#     -h, --help         Display usage information
#
# EXAMPLES:
#   # Install latest stable release
#   ./upstall-pwsh-macos.sh
#
#   # Install specific version
#   ./upstall-pwsh-macos.sh --tag v7.5.4
#
#   # Download to ~/Downloads and keep package
#   ./upstall-pwsh-macos.sh --out-dir "$HOME/Downloads" --keep
#
#   # Uninstall PowerShell
#   ./upstall-pwsh-macos.sh --uninstall
#
# NOTES:
#   - Installs to /usr/local/microsoft/powershell/<version>
#   - Creates symlink at /usr/local/bin/pwsh
#   - Automatically detects architecture (arm64 or x64)
#   - Verifies Microsoft code signature and SHA256 checksums
#   - Validates disk space before installation
#   - Default behavior downloads latest stable release (not preview/RC)
#
# Author: Jon LaBelle
# Source: https://github.com/jonlabelle/pwsh-upstall/blob/main/upstall-pwsh-macos.sh

REPO_OWNER="PowerShell"
REPO_NAME="PowerShell"
API_BASE="https://api.github.com/repos/${REPO_OWNER}/${REPO_NAME}"

DRY_RUN=0
TAG="" # e.g., v7.5.4
KEEP=0
OUT_DIR="" # optional destination directory for the downloaded pkg
FORCE=0
UNINSTALL=0
SKIP_CHECKSUM=0
TMP_DIR=""

cleanup_on_error() {
  if [[ -n "${TMP_DIR}" && -d "${TMP_DIR}" ]]; then
    log "Cleaning up temporary files due to error..."
    rm -rf "${TMP_DIR}" 2>/dev/null || true
  fi
}

trap cleanup_on_error EXIT INT TERM

usage() {
  cat <<'USAGE'
Usage:
  upstall-pwsh-macos.sh [options]

Options:
  --tag <tag>        Install a specific GitHub release tag (e.g., v7.5.4).
                     If omitted, installs the latest stable release.
  --out-dir <dir>    Directory to save the downloaded .pkg (default: temp dir).
  --keep             Keep the downloaded .pkg after installation (default: delete unless --out-dir is used).
  --force            Reinstall even if the target version is already installed.
  --uninstall        Uninstall PowerShell from the default install location.
  --skip-checksum    Skip SHA256 checksum verification (not recommended).
  -n, --dry-run      Show what would happen, but do not download or install.
  -h, --help         Show help.

Examples:
  # Install latest stable PowerShell
  ./upstall-pwsh-macos.sh

  # Install a specific version
  ./upstall-pwsh-macos.sh --tag v7.5.4

  # Download to ~/Downloads and keep the package
  ./upstall-pwsh-macos.sh --out-dir "$HOME/Downloads" --keep

  # Preview actions only
  ./upstall-pwsh-macos.sh --dry-run

  # Reinstall even if already on the target version
  ./upstall-pwsh-macos.sh --force

  # Uninstall PowerShell
  ./upstall-pwsh-macos.sh --uninstall
USAGE
}

log() { printf '%s\n' "$*"; }
run() {
  if [[ "${DRY_RUN}" -eq 1 ]]; then
    log "[dry-run] $*"
  else
    "$@"
  fi
}

need_cmd() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "ERROR: missing required command: $1" >&2

    # Suggest installation command based on available package manager
    local cmd="$1"
    local pkg="$1"

    # Map command names to common package names
    case "${cmd}" in
    shasum)
      echo "Note: shasum is typically included with macOS by default" >&2
      ;;
    python3)
      if command -v brew >/dev/null 2>&1; then
        echo "Try: brew install python3" >&2
      else
        echo "Try: Install Xcode Command Line Tools with 'xcode-select --install'" >&2
        echo "Or install Homebrew from https://brew.sh and run: brew install python3" >&2
      fi
      ;;
    *)
      if command -v brew >/dev/null 2>&1; then
        echo "Try: brew install ${pkg}" >&2
      else
        echo "Tip: Install Homebrew from https://brew.sh" >&2
      fi
      ;;
    esac

    exit 1
  }
}

check_network() {
  # Skip network check in dry-run mode to allow preview without connectivity
  if [[ "${DRY_RUN}" -eq 1 ]]; then
    return 0
  fi

  if ! curl -fsSL --connect-timeout 5 --max-time 10 "https://api.github.com" >/dev/null 2>&1; then
    echo "ERROR: Cannot reach GitHub API. Check your internet connection." >&2
    exit 1
  fi
}

check_disk_space() {
  local target_dir="${1}"
  local required_mb="${2:-500}"

  if ! command -v df >/dev/null 2>&1; then
    log "Warning: 'df' command not found, skipping disk space check"
    return 0
  fi

  local available_kb
  available_kb=$(df -k "${target_dir}" 2>/dev/null | awk 'NR==2 {print $4}')

  if [[ -z "${available_kb}" ]]; then
    log "Warning: Could not determine available disk space"
    return 0
  fi

  local available_mb=$((available_kb / 1024))

  if [[ "${available_mb}" -lt "${required_mb}" ]]; then
    echo "ERROR: Insufficient disk space. Required: ${required_mb}MB, Available: ${available_mb}MB" >&2
    exit 1
  fi

  log "Disk space check passed: ${available_mb}MB available"
}

compare_versions() {
  local v1="${1#v}"
  local v2="${2#v}"

  "${PYTHON}" - "${v1}" "${v2}" <<'PY'
import sys
try:
    from packaging import version
    v1 = version.parse(sys.argv[1])
    v2 = version.parse(sys.argv[2])
    if v1 == v2:
        sys.exit(0)
    elif v1 < v2:
        sys.exit(1)
    else:
        sys.exit(2)
except ImportError:
    # Fallback to string comparison if packaging module not available
    if sys.argv[1] == sys.argv[2]:
        sys.exit(0)
    elif sys.argv[1] < sys.argv[2]:
        sys.exit(1)
    else:
        sys.exit(2)
except Exception:
    # Fallback to string comparison on any other error
    if sys.argv[1] == sys.argv[2]:
        sys.exit(0)
    elif sys.argv[1] < sys.argv[2]:
        sys.exit(1)
    else:
        sys.exit(2)
PY
}

get_release_metadata() {
  local release_url="${1}"
  local target_pkg_suffix="${2}"

  log "Fetching release metadata: ${release_url}" >&2

  local json
  # Use GitHub token if available (avoids rate limiting in CI environments)
  if [[ -n "${GITHUB_TOKEN:-}" ]]; then
    json="$(curl -fsSL --retry 3 --retry-delay 2 -H "Authorization: Bearer ${GITHUB_TOKEN}" "${release_url}")"
  else
    json="$(curl -fsSL --retry 3 --retry-delay 2 "${release_url}")"
  fi

  # Extract (1) tag_name, (2) matching .pkg download URL, and (3) SHA256 file URL
  "${PYTHON}" - "${json}" "${target_pkg_suffix}" <<'PY'
import json, sys, re
data = json.loads(sys.argv[1])
target_suffix = sys.argv[2]

tag = data.get("tag_name") or ""

assets = data.get("assets") or []
candidates = []
for a in assets:
  name = a.get("name") or ""
  url  = a.get("browser_download_url") or ""
  # Prefer the official macOS pkg for the detected architecture
  if target_suffix in name and name.endswith(".pkg"):
    candidates.append((name, url))

# Prefer non-preview if multiple match
def score(item):
  name, _ = item
  s = 0
  if "preview" in name.lower(): s -= 10
  if "rc" in name.lower():      s -= 5
  # Prefer plain powershell-<ver>-osx-<arch>.pkg
  if re.match(rf"^powershell-.*-{re.escape(target_suffix)}$", name): s += 5
  return s

candidates.sort(key=score, reverse=True)

if not candidates:
  print(tag, "", "", "")
else:
  name, url = candidates[0]
  # Find corresponding SHA file
  sha_name = name + ".sha256"
  sha_url = ""
  for a in assets:
    if a.get("name") == sha_name:
      sha_url = a.get("browser_download_url") or ""
      break
  print(tag, url, name, sha_url)
PY
}

download_and_verify_package() {
  local pkg_url="${1}"
  local pkg_path="${2}"
  local sha_url="${3}"

  if [[ -f "${pkg_path}" ]]; then
    log "Removing existing incomplete download: ${pkg_path}"
    rm -f "${pkg_path}"
  fi

  log "Downloading to: ${pkg_path}"
  run curl -fL --retry 3 --retry-delay 2 -C - -o "${pkg_path}" "${pkg_url}"

  # Verify SHA256 checksum
  if [[ "${SKIP_CHECKSUM}" -eq 0 && -n "${sha_url}" ]]; then
    need_cmd shasum
    local sha_path="${pkg_path}.sha256"
    local dl_dir pkg_name
    dl_dir="$(dirname "${pkg_path}")"
    pkg_name="$(basename "${pkg_path}")"

    log "Downloading checksum file..."
    run curl -fsSL --retry 3 --retry-delay 2 -o "${sha_path}" "${sha_url}"

    log "Verifying SHA256 checksum..."
    cd "${dl_dir}"
    local expected_sha actual_sha
    expected_sha=$(cat "${sha_path}" | awk '{print $1}')
    actual_sha=$(shasum -a 256 "${pkg_name}" | awk '{print $1}')

    if [[ "${expected_sha}" != "${actual_sha}" ]]; then
      echo "ERROR: SHA256 checksum verification failed!" >&2
      echo "  Expected: ${expected_sha}" >&2
      echo "  Got:      ${actual_sha}" >&2
      exit 1
    fi
    log "SHA256 checksum verified successfully"
    rm -f "${sha_path}"
  elif [[ "${SKIP_CHECKSUM}" -eq 0 ]]; then
    log "Warning: SHA256 file not found, skipping checksum verification"
  fi

  # Verify Microsoft signature
  log "Checking package signature..."
  run pkgutil --check-signature "${pkg_path}"
  if [[ "${DRY_RUN}" -eq 0 ]]; then
    verify_microsoft_signature "${pkg_path}" || log "Warning: Could not verify Microsoft signature"
  fi
}

install_package() {
  local pkg_path="${1}"

  log "Installing PowerShell (requires sudo)…"
  run sudo installer -pkg "${pkg_path}" -target /

  # Verify
  log "Verifying installation…"
  run command -v pwsh
  # shellcheck disable=SC2016
  run pwsh -NoLogo -NoProfile -Command '$PSVersionTable.PSVersion'
}

main_install() {
  log "Checking network connectivity..."
  check_network

  # Decide which API endpoint to hit
  local release_url
  if [[ -n "${TAG}" ]]; then
    release_url="${API_BASE}/releases/tags/${TAG}"
  else
    release_url="${API_BASE}/releases/latest"
  fi

  local target_pkg_suffix="osx-${PKG_ARCH}.pkg"
  local rel_tag pkg_url pkg_name sha_url
  read -r rel_tag pkg_url pkg_name sha_url < <(get_release_metadata "${release_url}" "${target_pkg_suffix}")

  if [[ -z "${pkg_url}" ]]; then
    echo "ERROR: Could not find an ${target_pkg_suffix} asset in that release." >&2
    echo "Tip: Try specifying --tag (e.g., --tag v7.5.4) or check the release assets in the browser." >&2
    exit 1
  fi

  log "Selected PowerShell release: ${rel_tag:-<unknown tag>}"
  log "Selected package: ${pkg_name}"
  log "Download URL: ${pkg_url}"

  if [[ "${DRY_RUN}" -eq 1 ]]; then
    log "Dry-run summary:"
    log "  Would download: ${pkg_url}"
    log "  Would install : ${pkg_name}"
    log "  Would verify  : SHA256 checksum & Microsoft signature"
    log "  Would run     : sudo installer -pkg <downloaded-pkg> -target /"
    trap - EXIT TERM
    exit 0
  fi

  if [[ "${FORCE}" -eq 0 ]]; then
    local installed_version=""
    if command -v pwsh >/dev/null 2>&1; then
      # shellcheck disable=SC2016
      installed_version="$(pwsh -NoLogo -NoProfile -Command '$PSVersionTable.PSVersion.ToString()' 2>/dev/null || true)"
    fi

    if [[ -n "${rel_tag}" && -n "${installed_version}" ]]; then
      local desired_version="${rel_tag#v}"
      if [[ -n "${desired_version}" ]]; then
        compare_versions "${installed_version}" "${desired_version}"
        local version_cmp=$?
        if [[ ${version_cmp} -eq 0 ]]; then
          log "PowerShell ${installed_version} is already installed; skipping install. Use --force to reinstall."
          trap - EXIT INT TERM
          exit 0
        fi
      fi
    fi
  fi

  check_disk_space "/usr/local" 500

  # Determine download directory
  local dl_dir
  if [[ -n "${OUT_DIR}" ]]; then
    run mkdir -p "${OUT_DIR}"
    dl_dir="${OUT_DIR}"
    TMP_DIR=""
  else
    TMP_DIR="$(mktemp -d)"
    dl_dir="${TMP_DIR}"
  fi

  local pkg_path="${dl_dir%/}/${pkg_name}"

  download_and_verify_package "${pkg_url}" "${pkg_path}" "${sha_url}"
  install_package "${pkg_path}"

  # Cleanup
  if [[ "${KEEP}" -eq 1 || -n "${OUT_DIR}" ]]; then
    log "Keeping package at: ${pkg_path}"
  else
    if [[ -n "${TMP_DIR}" ]]; then
      log "Cleaning up temporary files…"
      run rm -rf "${TMP_DIR}"
      TMP_DIR=""
    fi
  fi

  trap - EXIT INT TERM
  log "Done."
}

verify_microsoft_signature() {
  local pkg_path="${1}"

  log "Verifying package signature..."
  if ! pkgutil --check-signature "${pkg_path}" 2>&1 | grep -q "Developer ID Installer: Microsoft Corporation"; then
    log "Warning: Package does not appear to be signed by Microsoft Corporation"
    log "Signature details:"
    pkgutil --check-signature "${pkg_path}" 2>&1 || true
    return 1
  fi

  log "Package signature verified: Microsoft Corporation"
  return 0
}

uninstall_pwsh() {
  local target_root="/usr/local/microsoft/powershell"
  local pwsh_link="/usr/local/bin/pwsh"
  local removed_any=0

  if [[ -d "${target_root}" ]]; then
    log "Uninstalling PowerShell from: ${target_root}"
    run sudo rm -rf "${target_root}"
    removed_any=1
  else
    log "No PowerShell install found at: ${target_root}"
  fi

  if [[ -L "${pwsh_link}" ]]; then
    local link_target=""
    link_target="$(readlink "${pwsh_link}" 2>/dev/null || true)"
    if [[ "${link_target}" == *"microsoft/powershell/"* ]]; then
      log "Removing symlink: ${pwsh_link}"
      run sudo rm -f "${pwsh_link}"
      removed_any=1
    fi
  fi

  if command -v pkgutil >/dev/null 2>&1; then
    local pkg_ids=""
    pkg_ids="$(pkgutil --pkgs | grep -i 'powershell' || true)"
    if [[ -n "${pkg_ids}" ]]; then
      while IFS= read -r pkg; do
        [[ -z "${pkg}" ]] && continue
        log "Forgetting package receipt: ${pkg}"
        run sudo pkgutil --forget "${pkg}"
      done <<<"${pkg_ids}"
    fi
  fi

  if [[ "${DRY_RUN}" -eq 1 ]]; then
    log "[dry-run] sudo rmdir \"/usr/local/microsoft/powershell\" (ignore failures)"
    log "[dry-run] sudo rmdir \"/usr/local/microsoft\" (ignore failures)"
  else
    sudo rmdir "/usr/local/microsoft/powershell" 2>/dev/null || true
    sudo rmdir "/usr/local/microsoft" 2>/dev/null || true
  fi

  if [[ "${removed_any}" -eq 1 ]]; then
    log "Uninstall complete."
  else
    log "Nothing to uninstall."
  fi

  # Check for user-specific directories that may need manual cleanup
  local user_dirs=()
  [[ -d "${HOME}/.config/powershell" ]] && user_dirs+=("${HOME}/.config/powershell")
  [[ -d "${HOME}/.local/share/powershell" ]] && user_dirs+=("${HOME}/.local/share/powershell")
  [[ -d "${HOME}/.cache/powershell" ]] && user_dirs+=("${HOME}/.cache/powershell")

  if [[ "${#user_dirs[@]}" -gt 0 ]]; then
    log ""
    log "Note: The following user-specific directories still exist and may be removed manually:"
    for dir in "${user_dirs[@]}"; do
      log "  ${dir}"
    done
    log "To remove them, run: rm -rf ~/.config/powershell ~/.local/share/powershell ~/.cache/powershell"
  fi
}

# Parse args
while [[ $# -gt 0 ]]; do
  case "$1" in
  --tag)
    TAG="${2:-}"
    shift 2
    ;;
  --out-dir)
    OUT_DIR="${2:-}"
    shift 2
    ;;
  --keep)
    KEEP=1
    shift
    ;;
  --force)
    FORCE=1
    shift
    ;;
  --uninstall)
    UNINSTALL=1
    shift
    ;;
  --skip-checksum)
    SKIP_CHECKSUM=1
    shift
    ;;
  -n | --dry-run)
    DRY_RUN=1
    shift
    ;;
  -h | --help)
    usage
    exit 0
    ;;
  *)
    echo "Unknown argument: $1" >&2
    usage
    exit 1
    ;;
  esac
done

need_cmd uname

if [[ "${UNINSTALL}" -eq 0 ]]; then
  need_cmd curl
  need_cmd pkgutil
  need_cmd installer
fi

if [[ "${UNINSTALL}" -eq 1 ]]; then
  trap - EXIT INT TERM
  uninstall_pwsh
  exit 0
fi

ARCH="$(uname -m)"
case "${ARCH}" in
arm64) PKG_ARCH="arm64" ;;
x86_64) PKG_ARCH="x64" ;;
*)
  echo "ERROR: Unsupported architecture: ${ARCH} (expected arm64 or x86_64)." >&2
  exit 1
  ;;
esac

log "Detected architecture: ${ARCH} -> selecting macOS ${PKG_ARCH} package"

PYTHON=""
if command -v python3 >/dev/null 2>&1; then
  PYTHON="python3"
elif command -v python >/dev/null 2>&1; then
  PYTHON="python"
else
  echo "ERROR: python3 (or python) is required to parse GitHub release JSON." >&2

  # Suggest installation method
  if command -v brew >/dev/null 2>&1; then
    echo "Try: brew install python3" >&2
  else
    echo "Try one of the following:" >&2
    echo "  1. Install Xcode Command Line Tools: xcode-select --install" >&2
    echo "  2. Install Homebrew (https://brew.sh) then run: brew install python3" >&2
    echo "  3. Download from https://www.python.org/downloads/macos/" >&2
  fi

  exit 1
fi

main_install
