#!/usr/bin/env sh
set -eu

# upstall-pwsh-linux.sh
#
# DESCRIPTION:
#   POSIX shell script to install, upgrade, or uninstall Microsoft PowerShell on Linux
#   using official GitHub release tarballs. Supports both glibc and musl-based distributions
#   (e.g., Alpine Linux) on x86_64 and ARM64 architectures.
#
# REQUIREMENTS:
#   - POSIX-compatible shell (/bin/sh)
#   - curl (for downloading releases)
#   - tar (for extracting tarballs)
#   - python3 or python (for JSON parsing and version comparison)
#   - sudo privileges (for installation to /usr/local)
#   - sha256sum (for checksum verification, can be skipped with --skip-checksum)
#
# USAGE:
#   ./upstall-pwsh-linux.sh [options]
#
#   Options:
#     --tag <tag>        Install specific GitHub release tag (e.g., v7.5.4)
#     --out-dir <dir>    Save downloaded tarball to specified directory
#     --keep             Retain tarball after installation
#     --force            Reinstall even if target version already installed
#     --uninstall        Remove PowerShell from /usr/local/microsoft/powershell
#     --skip-checksum    Skip SHA256 verification (not recommended)
#     -n, --dry-run      Preview actions without making changes
#     -h, --help         Display usage information
#
# EXAMPLES:
#   # Install latest stable release
#   ./upstall-pwsh-linux.sh
#
#   # Install specific version
#   ./upstall-pwsh-linux.sh --tag v7.5.4
#
#   # Preview installation without making changes
#   ./upstall-pwsh-linux.sh --dry-run
#
#   # Uninstall PowerShell
#   ./upstall-pwsh-linux.sh --uninstall
#
# NOTES:
#   - Installs to /usr/local/microsoft/powershell/<version>
#   - Creates symlink at /usr/local/bin/pwsh
#   - Automatically detects architecture and libc implementation
#   - Verifies SHA256 checksums and validates disk space before installation
#   - Default behavior downloads latest stable release (not preview/RC)
#
# Author: Jon LaBelle
# Source: https://github.com/jonlabelle/pwsh-upstall/blob/main/upstall-pwsh-linux.sh

REPO_OWNER="PowerShell"
REPO_NAME="PowerShell"
API_BASE="https://api.github.com/repos/${REPO_OWNER}/${REPO_NAME}"

DRY_RUN=0
TAG=""     # e.g., v7.5.4
OUT_DIR="" # destination directory for the downloaded tarball
KEEP=0
FORCE=0
UNINSTALL=0
SKIP_CHECKSUM=0
TMP_DIR=""

cleanup_on_error() {
  if [ -n "${TMP_DIR}" ] && [ -d "${TMP_DIR}" ]; then
    log "Cleaning up temporary files due to error..."
    rm -rf "${TMP_DIR}" 2>/dev/null || true
  fi
}

trap cleanup_on_error EXIT INT TERM

usage() {
  cat <<'USAGE'
Usage:
  upstall-pwsh-linux.sh [options]

Options:
  --tag <tag>        Install a specific GitHub release tag (e.g., v7.5.4).
                     If omitted, installs the latest stable release.
  --out-dir <dir>    Directory to save the downloaded tarball (default: temp dir).
  --keep             Keep the downloaded tarball after installation (default: delete unless --out-dir is used).
  --force            Reinstall even if the target version is already installed.
  --uninstall        Remove PowerShell from the default install location.
  --skip-checksum    Skip SHA256 checksum verification (not recommended).
  -n, --dry-run      Show what would happen, but do not download or install.
  -h, --help         Show help.

Examples:
  # Install latest stable PowerShell
  ./upstall-pwsh-linux.sh

  # Install a specific version
  ./upstall-pwsh-linux.sh --tag v7.5.4

  # Preview actions only
  ./upstall-pwsh-linux.sh --dry-run

  # Reinstall even if already on the target version
  ./upstall-pwsh-linux.sh --force

  # Uninstall PowerShell
  ./upstall-pwsh-linux.sh --uninstall
USAGE
}

log() { printf '%s\n' "$*"; }
run() {
  if [ "${DRY_RUN}" -eq 1 ]; then
    log "[dry-run] $*"
  else
    "$@"
  fi
}

need_cmd() {
  if ! command -v "${1}" >/dev/null 2>&1; then
    echo "ERROR: missing required command: ${1}" >&2

    # Suggest installation command based on available package manager
    _cmd="${1}"
    _pkg="${1}"

    # Map command names to common package names
    case "${_cmd}" in
    sha256sum) _pkg="coreutils" ;;
    python3) _pkg="python3" ;;
    *) _pkg="${_cmd}" ;;
    esac

    if command -v apt-get >/dev/null 2>&1; then
      echo "Try: sudo apt-get install ${_pkg}" >&2
    elif command -v dnf >/dev/null 2>&1; then
      echo "Try: sudo dnf install ${_pkg}" >&2
    elif command -v yum >/dev/null 2>&1; then
      echo "Try: sudo yum install ${_pkg}" >&2
    elif command -v apk >/dev/null 2>&1; then
      echo "Try: sudo apk add ${_pkg}" >&2
    elif command -v zypper >/dev/null 2>&1; then
      echo "Try: sudo zypper install ${_pkg}" >&2
    elif command -v pacman >/dev/null 2>&1; then
      echo "Try: sudo pacman -S ${_pkg}" >&2
    fi

    exit 1
  fi
}

check_network() {
  # Skip network check in dry-run mode to allow preview without connectivity
  if [ "${DRY_RUN}" -eq 1 ]; then
    return 0
  fi

  if ! curl -fsSL --connect-timeout 5 --max-time 10 "https://api.github.com" >/dev/null 2>&1; then
    echo "ERROR: Cannot reach GitHub API. Check your internet connection." >&2
    exit 1
  fi
}

check_disk_space() {
  _target_dir="${1}"
  _required_mb="${2:-500}"

  if ! command -v df >/dev/null 2>&1; then
    log "Warning: 'df' command not found, skipping disk space check"
    return 0
  fi

  _available_kb=$(df -k "${_target_dir}" 2>/dev/null | awk 'NR==2 {print $4}')

  if [ -z "${_available_kb}" ]; then
    log "Warning: Could not determine available disk space"
    return 0
  fi

  _available_mb=$((_available_kb / 1024))

  if [ "${_available_mb}" -lt "${_required_mb}" ]; then
    echo "ERROR: Insufficient disk space. Required: ${_required_mb}MB, Available: ${_available_mb}MB" >&2
    exit 1
  fi

  log "Disk space check passed: ${_available_mb}MB available"
}

compare_versions() {
  _v1="${1#v}"
  _v2="${2#v}"

  "${PYTHON}" - "${_v1}" "${_v2}" <<'PY'
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
  _release_url="${1}"
  _target_suffix="${2}"

  log "Fetching release metadata: ${_release_url}" >&2

  # Use GitHub token if available (avoids rate limiting in CI environments)
  if [ -n "${GITHUB_TOKEN:-}" ]; then
    _json="$(curl -fsSL --retry 3 --retry-delay 2 -H "Authorization: Bearer ${GITHUB_TOKEN}" "${_release_url}")"
  else
    _json="$(curl -fsSL --retry 3 --retry-delay 2 "${_release_url}")"
  fi

  _rel_data="$(
    "${PYTHON}" - "${_json}" "${_target_suffix}" <<'PY'
import json, sys, re
data = json.loads(sys.argv[1])
target = sys.argv[2]

tag = data.get("tag_name") or ""
assets = data.get("assets") or []
candidates = []
sha_url = ""
for a in assets:
    name = a.get("name") or ""
    url = a.get("browser_download_url") or ""
    if target in name and name.endswith(".tar.gz"):
        candidates.append((name, url))
    elif name.endswith(".tar.gz.sha256") and target in name:
        sha_url = url

def score(item):
    name, _ = item
    w = 0
    if "preview" in name.lower(): w -= 10
    if "rc" in name.lower(): w -= 5
    if re.match(rf"^powershell-.*-{re.escape(target)}$", name): w += 5
    return w

candidates.sort(key=score, reverse=True)
if candidates:
    name, url = candidates[0]
    # Find corresponding SHA file
    sha_name = name + ".sha256"
    for a in assets:
        if a.get("name") == sha_name:
            sha_url = a.get("browser_download_url") or ""
            break
    print(tag, url, name, sha_url)
else:
    print(tag, "", "", "")
PY
  )"

  printf '%s\n' "${_rel_data}"
}

download_and_verify_package() {
  _pkg_url="${1}"
  _pkg_path="${2}"
  _sha_url="${3}"

  if [ -f "${_pkg_path}" ]; then
    log "Removing existing incomplete download: ${_pkg_path}"
    rm -f "${_pkg_path}"
  fi

  log "Downloading to: ${_pkg_path}"
  run curl -fL --retry 3 --retry-delay 2 -C - -o "${_pkg_path}" "${_pkg_url}"

  if [ "${SKIP_CHECKSUM}" -eq 0 ] && [ -n "${_sha_url}" ]; then
    need_cmd sha256sum
    _sha_path="${_pkg_path}.sha256"
    _dl_dir="$(dirname "${_pkg_path}")"
    _pkg_name="$(basename "${_pkg_path}")"

    log "Downloading checksum file..."
    run curl -fsSL --retry 3 --retry-delay 2 -o "${_sha_path}" "${_sha_url}"

    log "Verifying SHA256 checksum..."
    cd "${_dl_dir}"
    _expected_sha=$(cat "${_sha_path}" | awk '{print $1}')
    _actual_sha=$(sha256sum "${_pkg_name}" | awk '{print $1}')

    if [ "${_expected_sha}" != "${_actual_sha}" ]; then
      echo "ERROR: SHA256 checksum verification failed!" >&2
      echo "  Expected: ${_expected_sha}" >&2
      echo "  Got:      ${_actual_sha}" >&2
      exit 1
    fi
    log "SHA256 checksum verified successfully"
    rm -f "${_sha_path}"
  elif [ "${SKIP_CHECKSUM}" -eq 0 ]; then
    log "Warning: SHA256 file not found, skipping checksum verification"
  fi
}

install_package() {
  _pkg_path="${1}"
  _install_version="${2}"
  _install_root="/usr/local/microsoft/powershell"
  _install_path="${_install_root}/${_install_version}"

  run ${SUDO}mkdir -p "${_install_path}"
  log "Extracting to: ${_install_path}"
  run ${SUDO}tar -xzf "${_pkg_path}" -C "${_install_path}"

  log "Linking pwsh to /usr/local/bin/pwsh"
  run ${SUDO}ln -sfn "${_install_path}/pwsh" "/usr/local/bin/pwsh"
}

main_install() {
  log "Checking network connectivity..."
  check_network

  if [ -n "${TAG}" ]; then
    RELEASE_URL="${API_BASE}/releases/tags/${TAG}"
  else
    RELEASE_URL="${API_BASE}/releases/latest"
  fi

  REL_DATA="$(get_release_metadata "${RELEASE_URL}" "${TARGET_SUFFIX}")"

  REL_TAG=$(printf '%s\n' "${REL_DATA}" | awk '{print $1}')
  PKG_URL=$(printf '%s\n' "${REL_DATA}" | awk '{print $2}')
  PKG_NAME=$(printf '%s\n' "${REL_DATA}" | awk '{print $3}')
  SHA_URL=$(printf '%s\n' "${REL_DATA}" | awk '{print $4}')

  if [ -z "${PKG_URL}" ]; then
    echo "ERROR: Could not find a ${TARGET_SUFFIX} asset in that release." >&2
    exit 1
  fi

  log "Selected PowerShell release: ${REL_TAG:-<unknown tag>}"
  log "Selected package: ${PKG_NAME}"
  log "Download URL: ${PKG_URL}"

  if [ "${DRY_RUN}" -eq 1 ]; then
    log "Dry-run summary:"
    log "  Would download: ${PKG_URL}"
    log "  Would install : ${PKG_NAME}"
    log "  Target arch   : ${PKG_ARCH} (musl=${MUSL})"
    log "  Would verify  : SHA256 checksum"
    log "  Would install to /usr/local/microsoft/powershell/<version>"
    trap - EXIT INT TERM
    exit 0
  fi

  INSTALLED_VERSION=""
  if command -v pwsh >/dev/null 2>&1; then
    # shellcheck disable=SC2016
    INSTALLED_VERSION="$(pwsh -NoLogo -NoProfile -Command '$PSVersionTable.PSVersion.ToString()' 2>/dev/null || true)"
  fi

  if [ "${FORCE}" -eq 0 ] && [ -n "${REL_TAG}" ] && [ -n "${INSTALLED_VERSION}" ]; then
    DESIRED_VERSION="${REL_TAG#v}"
    if [ -n "${DESIRED_VERSION}" ]; then
      compare_versions "${INSTALLED_VERSION}" "${DESIRED_VERSION}"
      _cmp=$?
      if [ "${_cmp}" -eq 0 ]; then
        log "PowerShell ${INSTALLED_VERSION} is already installed; use --force to reinstall."
        exit 0
      fi
    fi
  fi

  check_disk_space "/usr/local" 500

  if [ -n "${OUT_DIR}" ]; then
    run mkdir -p "${OUT_DIR}"
    DL_DIR="${OUT_DIR}"
    TMP_DIR=""
  else
    TMP_DIR="$(mktemp -d)"
    DL_DIR="${TMP_DIR}"
  fi

  PKG_PATH="${DL_DIR%/}/${PKG_NAME}"

  download_and_verify_package "${PKG_URL}" "${PKG_PATH}" "${SHA_URL}"

  DESIRED_VERSION="${REL_TAG#v}"
  install_package "${PKG_PATH}" "${DESIRED_VERSION}"

  if [ "${KEEP}" -eq 1 ] || [ -n "${OUT_DIR}" ]; then
    log "Keeping tarball at: ${PKG_PATH}"
  else
    if [ -n "${TMP_DIR}" ]; then
      log "Cleaning up temporary files..."
      rm -rf "${TMP_DIR}"
      TMP_DIR=""
    fi
  fi

  trap - EXIT INT TERM
  log "Done. Verify with: pwsh -v"
}

while [ $# -gt 0 ]; do
  case "${1}" in
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
    echo "Unknown argument: ${1}" >&2
    usage
    exit 1
    ;;
  esac
done

SUDO=""
if [ "$(id -u)" -ne 0 ]; then
  if command -v sudo >/dev/null 2>&1; then
    SUDO="sudo"
  else
    if [ "${DRY_RUN}" -eq 1 ]; then
      SUDO="sudo"
    else
      echo "ERROR: this script needs root privileges (installing to /usr/local). Please run as root or install sudo." >&2
      exit 1
    fi
  fi
fi

need_cmd uname
need_cmd curl
need_cmd tar

if [ "${UNINSTALL}" -eq 1 ]; then
  trap - EXIT INT TERM
  INSTALL_ROOT="/usr/local/microsoft/powershell"
  if [ -d "${INSTALL_ROOT}" ]; then
    log "Removing ${INSTALL_ROOT}"
    run ${SUDO}rm -rf "${INSTALL_ROOT}"
  else
    log "No PowerShell install found at ${INSTALL_ROOT}"
  fi
  if [ -L "/usr/local/bin/pwsh" ]; then
    log "Removing /usr/local/bin/pwsh"
    run ${SUDO}rm -f "/usr/local/bin/pwsh"
  fi
  log "Uninstall complete."

  # Check for user-specific directories that may need manual cleanup
  USER_DIRS=""
  if [ -d "${HOME}/.config/powershell" ]; then
    USER_DIRS="${USER_DIRS}  ${HOME}/.config/powershell\n"
  fi
  if [ -d "${HOME}/.local/share/powershell" ]; then
    USER_DIRS="${USER_DIRS}  ${HOME}/.local/share/powershell\n"
  fi
  if [ -d "${HOME}/.cache/powershell" ]; then
    USER_DIRS="${USER_DIRS}  ${HOME}/.cache/powershell\n"
  fi

  if [ -n "${USER_DIRS}" ]; then
    log ""
    log "Note: The following user-specific directories still exist and may be removed manually:"
    printf "${USER_DIRS}"
    log "To remove them, run: rm -rf ~/.config/powershell ~/.local/share/powershell ~/.cache/powershell"
  fi

  exit 0
fi

ARCH="$(uname -m)"
case "${ARCH}" in
x86_64) PKG_ARCH="x64" ;;
aarch64 | arm64) PKG_ARCH="arm64" ;;
*)
  echo "ERROR: Unsupported architecture: ${ARCH} (expected x86_64 or arm64)." >&2
  exit 1
  ;;
esac

MUSL=0
if command -v ldd >/dev/null 2>&1 && ldd --version 2>&1 | grep -qi musl; then
  MUSL=1
fi

if [ "${MUSL}" -eq 1 ]; then
  TARGET_SUFFIX="linux-musl-${PKG_ARCH}.tar.gz"
else
  TARGET_SUFFIX="linux-${PKG_ARCH}.tar.gz"
fi

PYTHON=""
if command -v python3 >/dev/null 2>&1; then
  PYTHON="python3"
elif command -v python >/dev/null 2>&1; then
  PYTHON="python"
else
  echo "ERROR: python3 (or python) is required to parse GitHub release JSON." >&2

  # Suggest installation based on package manager
  if command -v apt-get >/dev/null 2>&1; then
    echo "Try: sudo apt-get install python3" >&2
  elif command -v dnf >/dev/null 2>&1; then
    echo "Try: sudo dnf install python3" >&2
  elif command -v yum >/dev/null 2>&1; then
    echo "Try: sudo yum install python3" >&2
  elif command -v apk >/dev/null 2>&1; then
    echo "Try: sudo apk add python3" >&2
  elif command -v zypper >/dev/null 2>&1; then
    echo "Try: sudo zypper install python3" >&2
  elif command -v pacman >/dev/null 2>&1; then
    echo "Try: sudo pacman -S python" >&2
  fi

  exit 1
fi

main_install
