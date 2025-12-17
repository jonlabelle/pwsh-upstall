#!/usr/bin/env bash
set -euo pipefail

# install-pwsh-macos.sh
#
# Downloads and installs Microsoft PowerShell for macOS (arm64) from GitHub Releases.
#
# Notes:
# - Default behavior installs the latest *stable* release from GitHub (/releases/latest).
# - macOS installer packages are distributed via the official PowerShell GitHub Releases.
#
# Requirements:
# - macOS 13+ (you are on macOS Tahoe 26.1)
# - curl
# - sudo privileges (for installation/uninstall)
# - python3 OR python (used to parse GitHub JSON reliably; avoids needing jq)

REPO_OWNER="PowerShell"
REPO_NAME="PowerShell"
API_BASE="https://api.github.com/repos/${REPO_OWNER}/${REPO_NAME}"

DRY_RUN=0
TAG="" # e.g., v7.5.4
KEEP_PKG=0
OUT_DIR="" # optional destination directory for the downloaded pkg
FORCE=0
UNINSTALL=0

usage() {
  cat <<'USAGE'
Usage:
  install-pwsh-macos.sh [options]

Options:
  --tag <tag>        Install a specific GitHub release tag (e.g., v7.5.4).
                     If omitted, installs the latest stable release.
  --out-dir <dir>    Directory to save the downloaded .pkg (default: temp dir).
  --keep-pkg         Keep the downloaded .pkg after installation (default: delete unless --out-dir is used).
  --force            Reinstall even if the target version is already installed.
  --uninstall        Uninstall PowerShell from the default install location.
  -n, --dry-run      Show what would happen, but do not download or install.
  -h, --help         Show help.

Examples:
  # Install latest stable PowerShell (arm64)
  ./install-pwsh-macos.sh

  # Install a specific version
  ./install-pwsh-macos.sh --tag v7.5.4

  # Download to ~/Downloads and keep the package
  ./install-pwsh-macos.sh --out-dir "$HOME/Downloads" --keep-pkg

  # Preview actions only
  ./install-pwsh-macos.sh --dry-run

  # Reinstall even if already on the target version
  ./install-pwsh-macos.sh --force

  # Uninstall PowerShell
  ./install-pwsh-macos.sh --uninstall
USAGE
}

log() { printf '%s\n' "$*"; }
run() {
  if [[ "${DRY_RUN}" -eq 1 ]]; then
    log "[dry-run] $*"
  else
    eval "$@"
  fi
}

need_cmd() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "ERROR: missing required command: $1" >&2
    exit 1
  }
}

uninstall_pwsh() {
  local target_root="/usr/local/microsoft/powershell"
  local pwsh_link="/usr/local/bin/pwsh"
  local removed_any=0

  if [[ -d "${target_root}" ]]; then
    log "Uninstalling PowerShell from: ${target_root}"
    run "sudo rm -rf \"${target_root}\""
    removed_any=1
  else
    log "No PowerShell install found at: ${target_root}"
  fi

  if [[ -L "${pwsh_link}" ]]; then
    local link_target=""
    link_target="$(readlink "${pwsh_link}" 2>/dev/null || true)"
    if [[ "${link_target}" == *"microsoft/powershell/"* ]]; then
      log "Removing symlink: ${pwsh_link}"
      run "sudo rm -f \"${pwsh_link}\""
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
        run "sudo pkgutil --forget \"${pkg}\""
      done <<<"${pkg_ids}"
    fi
  fi

  run "sudo rmdir \"/usr/local/microsoft/powershell\" 2>/dev/null || true"
  run "sudo rmdir \"/usr/local/microsoft\" 2>/dev/null || true"

  if [[ "${removed_any}" -eq 1 ]]; then
    log "Uninstall complete."
  else
    log "Nothing to uninstall."
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
  --keep-pkg)
    KEEP_PKG=1
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
  uninstall_pwsh
  exit 0
fi

ARCH="$(uname -m)"
if [[ "$ARCH" != "arm64" ]]; then
  echo "ERROR: This script is intended for Apple Silicon (arm64). Detected: $ARCH" >&2
  exit 1
fi

PYTHON=""
if command -v python3 >/dev/null 2>&1; then
  PYTHON="python3"
elif command -v python >/dev/null 2>&1; then
  PYTHON="python"
else
  echo "ERROR: python3 (or python) is required to parse GitHub release JSON." >&2
  echo "Tip: install python3 (e.g., via Xcode Command Line Tools or a python installer)." >&2
  exit 1
fi

# Decide which API endpoint to hit
if [[ -n "$TAG" ]]; then
  RELEASE_URL="${API_BASE}/releases/tags/${TAG}"
else
  RELEASE_URL="${API_BASE}/releases/latest"
fi

log "Fetching release metadata: ${RELEASE_URL}"
# Dry-run should still fetch metadata so we can show the exact asset we'd pick.
JSON="$(curl -fsSL "${RELEASE_URL}")"

# Extract (1) tag_name and (2) matching .pkg download URL for macOS arm64
# We select assets containing "osx-arm64.pkg" and avoid preview naming patterns where possible.
read -r REL_TAG PKG_URL PKG_NAME < <(
  "${PYTHON}" - "${JSON}" <<'PY'
import json, sys, re
data = json.loads(sys.argv[1])

tag = data.get("tag_name") or ""

assets = data.get("assets") or []
candidates = []
for a in assets:
  name = a.get("name") or ""
  url  = a.get("browser_download_url") or ""
  # Prefer the official macOS arm64 pkg
  if "osx-arm64.pkg" in name and name.endswith(".pkg"):
    candidates.append((name, url))

# Prefer non-preview if multiple match
def score(item):
  name, _ = item
  s = 0
  if "preview" in name.lower(): s -= 10
  if "rc" in name.lower():      s -= 5
  # Prefer plain powershell-<ver>-osx-arm64.pkg
  if re.match(r"^powershell-.*-osx-arm64\.pkg$", name): s += 5
  return s

candidates.sort(key=score, reverse=True)

if not candidates:
  print(tag, "", "")
else:
  name, url = candidates[0]
  print(tag, url, name)
PY
)

if [[ -z "${PKG_URL}" ]]; then
  echo "ERROR: Could not find an osx-arm64.pkg asset in that release." >&2
  echo "Tip: Try specifying --tag (e.g., --tag v7.5.4) or check the release assets in the browser." >&2
  exit 1
fi

log "Selected PowerShell release: ${REL_TAG:-<unknown tag>}"
log "Selected package: ${PKG_NAME}"
log "Download URL: ${PKG_URL}"

if [[ "${FORCE}" -eq 0 ]]; then
  INSTALLED_VERSION=""
  if command -v pwsh >/dev/null 2>&1; then
    INSTALLED_VERSION="$(pwsh -NoLogo -NoProfile -Command '$PSVersionTable.PSVersion.ToString()' 2>/dev/null || true)"
  fi

  if [[ -n "${REL_TAG}" && -n "${INSTALLED_VERSION}" ]]; then
    DESIRED_VERSION="${REL_TAG#v}"
    if [[ -n "${DESIRED_VERSION}" && "${INSTALLED_VERSION}" == "${DESIRED_VERSION}" ]]; then
      if [[ "${DRY_RUN}" -eq 1 ]]; then
        log "PowerShell ${INSTALLED_VERSION} is already installed; would skip install (use --force to reinstall)."
      else
        log "PowerShell ${INSTALLED_VERSION} is already installed; skipping install. Use --force to reinstall."
      fi
      exit 0
    fi
  fi
fi

if [[ "${DRY_RUN}" -eq 1 ]]; then
  log "Dry-run summary:"
  log "  Would download: ${PKG_URL}"
  log "  Would install : ${PKG_NAME}"
  log "  Would run     : sudo installer -pkg <downloaded-pkg> -target /"
  exit 0
fi

# Determine download directory
TMP_DIR=""
if [[ -n "${OUT_DIR}" ]]; then
  if [[ "${DRY_RUN}" -eq 1 ]]; then
    log "[dry-run] mkdir -p \"${OUT_DIR}\""
  else
    mkdir -p "${OUT_DIR}"
  fi
  DL_DIR="${OUT_DIR}"
else
  # temp dir
  if [[ "${DRY_RUN}" -eq 1 ]]; then
    DL_DIR="/tmp/<temp-dir>"
  else
    TMP_DIR="$(mktemp -d)"
    DL_DIR="${TMP_DIR}"
  fi
fi

PKG_PATH="${DL_DIR%/}/${PKG_NAME}"

# Download
log "Downloading to: ${PKG_PATH}"
run "curl -fL --retry 3 --retry-delay 2 -o \"${PKG_PATH}\" \"${PKG_URL}\""

# Verify installer signature (Gatekeeper-style signature check for .pkg)
log "Checking package signature (pkgutil --check-signature)…"
run "pkgutil --check-signature \"${PKG_PATH}\""

# Install
log "Installing PowerShell (requires sudo)…"
run "sudo installer -pkg \"${PKG_PATH}\" -target /"

# Verify
log "Verifying installation…"
run "command -v pwsh"
run "pwsh -NoLogo -NoProfile -Command '\$PSVersionTable.PSVersion'"

# Cleanup
if [[ "${KEEP_PKG}" -eq 1 || -n "${OUT_DIR}" ]]; then
  log "Keeping package at: ${PKG_PATH}"
else
  if [[ -n "${TMP_DIR}" ]]; then
    log "Cleaning up temporary files…"
    run "rm -rf \"${TMP_DIR}\""
  else
    # If temp dir wasn't created (e.g. dry-run), do nothing
    :
  fi
fi

log "Done."
