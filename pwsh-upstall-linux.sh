#!/usr/bin/env sh
set -eu

# pwsh-upstall-linux.sh
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
#   ./pwsh-upstall-linux.sh [options]
#
#   Options:
#     --tag <tag>        Select release by semver/tag:
#                        - v7      => latest 7.x.x (major track)
#                        - v7.5    => latest 7.5.x (minor track)
#                        - v7.5.4  => specific patch release
#                        - other tags (e.g., preview) are resolved exactly
#                        Prereleases are supported only via explicit exact tag;
#                        default/latest/major/minor selection is stable-only.
#     --out-dir <dir>    Save downloaded tarball to specified directory
#     --keep             Retain tarball after installation
#     --force            Reinstall even if target version already installed
#     --keep-old-version Preserve the previously installed version when upgrading
#     --check            Only check if installed version is up to date
#     --uninstall        Remove PowerShell from /usr/local/microsoft/powershell
#     --skip-checksum    Skip SHA256 verification (not recommended)
#     -n, --dry-run      Preview actions without making changes
#     -h, --help         Display usage information
#
# EXAMPLES:
#   # Install latest stable release
#   ./pwsh-upstall-linux.sh
#
#   # Install latest 7.x release
#   ./pwsh-upstall-linux.sh --tag v7
#
#   # Install latest 7.5.x release
#   ./pwsh-upstall-linux.sh --tag v7.5
#
#   # Install specific patch version
#   ./pwsh-upstall-linux.sh --tag v7.5.4
#
#   # Preview installation without making changes
#   ./pwsh-upstall-linux.sh --dry-run
#
#   # Check if PowerShell is up to date
#   ./pwsh-upstall-linux.sh --check
#
#   # Uninstall PowerShell
#   ./pwsh-upstall-linux.sh --uninstall
#
# NOTES:
#   - Installs to /usr/local/microsoft/powershell/<version>
#   - Creates symlink at /usr/local/bin/pwsh
#   - Automatically detects architecture and libc implementation
#   - Verifies SHA256 checksums and validates disk space before installation
#   - Removes the previously active version after a successful upgrade
#     unless --keep-old-version is used
#   - Default behavior downloads latest stable release (not preview/RC)
#   - Prereleases are supported only via explicit exact tag
#     (default/latest/major/minor selection is stable-only)
#
# Author: Jon LaBelle
# Source: https://github.com/jonlabelle/pwsh-upstall/blob/main/pwsh-upstall-linux.sh

API_BASE="https://api.github.com/repos/PowerShell/PowerShell"

DRY_RUN=0
TAG=""     # e.g., v7.5.4
OUT_DIR="" # destination directory for the downloaded tarball
KEEP=0
FORCE=0
KEEP_OLD_VERSION=0
UNINSTALL=0
SKIP_CHECKSUM=0
CHECK_ONLY=0
TMP_DIR=""

# ANSI colors (disabled when not on a TTY or NO_COLOR is set)
if [ -t 1 ] && [ -z "${NO_COLOR:-}" ]; then
  C_RESET="$(printf '\033[0m')"
  C_RED="$(printf '\033[31m')"
  C_GREEN="$(printf '\033[32m')"
  C_YELLOW="$(printf '\033[33m')"
  C_CYAN="$(printf '\033[36m')"
else
  C_RESET=""
  C_RED=""
  C_GREEN=""
  C_YELLOW=""
  C_CYAN=""
fi

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
  pwsh-upstall-linux.sh [options]

Options:
  --tag <tag>        Select release by semver/tag:
                     - v7      => latest 7.x.x (major track)
                     - v7.5    => latest 7.5.x (minor track)
                     - v7.5.4  => specific patch release
                     - other tags (e.g., preview) are resolved exactly
                     If omitted (or set to 'latest'), installs the latest stable release.
                     Prereleases are supported only via explicit exact tag.
  --out-dir <dir>    Directory to save the downloaded tarball (default: temp dir).
  --keep             Keep the downloaded tarball after installation (default: delete unless --out-dir is used).
  --force            Reinstall even if the target version is already installed.
  --keep-old-version Keep the previously installed version when upgrading.
  --check            Only check if installed version is up to date; no download or install.
  --uninstall        Remove PowerShell from the default install location.
  --skip-checksum    Skip SHA256 checksum verification (not recommended).
  -n, --dry-run      Show what would happen, but do not download or install.
  -h, --help         Show help.

Examples:
  # Install latest stable PowerShell
  ./pwsh-upstall-linux.sh

  # Install latest release in major line 7.x
  ./pwsh-upstall-linux.sh --tag v7

  # Install latest release in minor line 7.5.x
  ./pwsh-upstall-linux.sh --tag v7.5

  # Install a specific patch version
  ./pwsh-upstall-linux.sh --tag v7.5.4

  # Preview actions only
  ./pwsh-upstall-linux.sh --dry-run

  # Check if PowerShell is up to date
  ./pwsh-upstall-linux.sh --check

  # Reinstall even if already on the target version
  ./pwsh-upstall-linux.sh --force

  # Uninstall PowerShell
  ./pwsh-upstall-linux.sh --uninstall
USAGE
}

log() { printf '%s\n' "$*"; }
log_info() { printf '%s\n' "${C_CYAN}$*${C_RESET}"; }
log_warn() { printf '%s\n' "${C_YELLOW}$*${C_RESET}"; }
log_success() { printf '%s\n' "${C_GREEN}$*${C_RESET}"; }
log_error() { printf '%s\n' "${C_RED}$*${C_RESET}" >&2; }

run() {
  if [ "${DRY_RUN}" -eq 1 ]; then
    log "[dry-run] $*"
  else
    "$@"
  fi
}

need_cmd() {
  if ! command -v "${1}" >/dev/null 2>&1; then
    log_error "ERROR: missing required command: ${1}"

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

  _status=""
  if [ -n "${GITHUB_TOKEN:-}" ]; then
    _status="$(curl -sSL --connect-timeout 5 --max-time 10 -o /dev/null -w "%{http_code}" -H "Authorization: Bearer ${GITHUB_TOKEN}" "https://api.github.com" 2>/dev/null || true)"
  else
    _status="$(curl -sSL --connect-timeout 5 --max-time 10 -o /dev/null -w "%{http_code}" "https://api.github.com" 2>/dev/null || true)"
  fi

  if [ -z "${_status}" ] || [ "${_status}" = "000" ] || [ "${_status}" -ge 500 ]; then
    log_error "ERROR: Cannot reach GitHub API. Check your internet connection."
    exit 1
  fi
}

check_disk_space() {
  _target_dir="${1}"
  _required_mb="${2:-500}"

  if ! command -v df >/dev/null 2>&1; then
    log_warn "Warning: 'df' command not found, skipping disk space check"
    return 0
  fi

  _available_kb=$(df -k "${_target_dir}" 2>/dev/null | awk 'NR==2 {print $4}')

  if [ -z "${_available_kb}" ]; then
    log_warn "Warning: Could not determine available disk space"
    return 0
  fi

  _available_mb=$((_available_kb / 1024))

  if [ "${_available_mb}" -lt "${_required_mb}" ]; then
    log_error "ERROR: Insufficient disk space. Required: ${_required_mb}MB, Available: ${_available_mb}MB"
    exit 1
  fi

  log_success "Disk space check passed: ${_available_mb}MB available"
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

extract_expected_sha256() {
  _checksum_path="${1}"
  _asset_name="${2}"

  "${PYTHON}" - "${_checksum_path}" "${_asset_name}" <<'PY'
import os, sys

checksum_path = sys.argv[1]
asset_name = sys.argv[2]
asset_basename = os.path.basename(asset_name)

with open(checksum_path, "r", encoding="utf-8", errors="replace") as f:
    lines = [line.strip() for line in f if line.strip()]

for line in lines:
    parts = line.split()
    if len(parts) < 2:
        continue

    candidate = parts[-1].lstrip("*")
    candidate_basename = os.path.basename(candidate)
    if candidate == asset_name or candidate_basename == asset_basename:
        print(parts[0])
        sys.exit(0)

if lines:
    parts = lines[0].split()
    if parts:
        print(parts[0])
        sys.exit(0)

sys.exit(1)
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
hashes_url = ""
for a in assets:
    name = a.get("name") or ""
    url = a.get("browser_download_url") or ""
    if name == "hashes.sha256":
        hashes_url = url
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
    if not sha_url:
        sha_url = hashes_url
    print(tag, url, name, sha_url)
else:
    print(tag, "", "", "")
PY
  )"

  printf '%s\n' "${_rel_data}"
}

github_api_get() {
  _url="${1}"
  if [ -n "${GITHUB_TOKEN:-}" ]; then
    curl -fsSL --retry 3 --retry-delay 2 -H "Authorization: Bearer ${GITHUB_TOKEN}" "${_url}"
  else
    curl -fsSL --retry 3 --retry-delay 2 "${_url}"
  fi
}

is_numeric_semver_selector() {
  _selector="${1}"
  printf '%s\n' "${_selector}" | grep -Eiq '^[vV]?[0-9]+(\.[0-9]+){0,2}$'
}

semver_selector_part_count() {
  _selector="${1#v}"
  _selector="${_selector#V}"
  printf '%s\n' "${_selector}" | awk -F'.' '{print NF}'
}

get_release_metadata_by_semver_selector() {
  _selector="${1}"
  _target_suffix="${2}"
  _selector_no_v="${_selector#v}"
  _selector_no_v="${_selector_no_v#V}"

  log "Resolving semver selector: ${_selector}" >&2

  _json_file="$(mktemp)"
  github_api_get "${API_BASE}/releases?per_page=100" >"${_json_file}"
  _rel_data="$(
    "${PYTHON}" - "${_json_file}" "${_target_suffix}" "${_selector_no_v}" <<'PY'
import json, re, sys

with open(sys.argv[1], "r", encoding="utf-8") as f:
    releases = json.load(f)
target = sys.argv[2]
selector = (sys.argv[3] or "").strip()

parts = selector.split(".")
if not parts or len(parts) > 2 or any(not p.isdigit() for p in parts):
    print("", "", "", "")
    sys.exit(0)

want = tuple(int(p) for p in parts)

def parse_version_tag(tag):
    m = re.match(r"^v?(\d+)\.(\d+)\.(\d+)$", tag or "")
    if not m:
        return None
    return tuple(int(g) for g in m.groups())

def pick_asset(release):
    assets = release.get("assets") or []
    candidates = []
    sha_url = ""
    hashes_url = ""

    for asset in assets:
        name = asset.get("name") or ""
        url = asset.get("browser_download_url") or ""
        if name == "hashes.sha256":
            hashes_url = url
        if target in name and name.endswith(".tar.gz"):
            candidates.append((name, url))
        elif name.endswith(".tar.gz.sha256") and target in name:
            sha_url = url

    def score(item):
        name, _ = item
        w = 0
        lname = name.lower()
        if "preview" in lname:
            w -= 10
        if "rc" in lname:
            w -= 5
        if re.match(rf"^powershell-.*-{re.escape(target)}$", name):
            w += 5
        return w

    candidates.sort(key=score, reverse=True)
    if not candidates:
        return None

    name, url = candidates[0]
    sha_name = name + ".sha256"
    for asset in assets:
        if (asset.get("name") or "") == sha_name:
            sha_url = asset.get("browser_download_url") or ""
            break
    if not sha_url:
        sha_url = hashes_url

    return url, name, sha_url

matches = []
for release in releases:
    if release.get("draft") or release.get("prerelease"):
        continue

    tag = release.get("tag_name") or ""
    version = parse_version_tag(tag)
    if version is None:
        continue

    if len(want) == 1 and version[0] != want[0]:
        continue
    if len(want) == 2 and version[:2] != want:
        continue

    asset = pick_asset(release)
    if not asset:
        continue

    url, name, sha_url = asset
    matches.append((version, tag, url, name, sha_url))

matches.sort(key=lambda x: x[0], reverse=True)
if matches:
    _, tag, url, name, sha_url = matches[0]
    print(tag, url, name, sha_url)
else:
    print("", "", "", "")
PY
  )"
  rm -f "${_json_file}"

  printf '%s\n' "${_rel_data}"
}

resolve_release_metadata() {
  _selector="${1:-}"
  _target_suffix="${2}"
  _selector_lc="$(printf '%s' "${_selector}" | tr '[:upper:]' '[:lower:]')"

  if [ -z "${_selector}" ] || [ "${_selector_lc}" = "latest" ]; then
    get_release_metadata "${API_BASE}/releases/latest" "${_target_suffix}"
    return
  fi

  if is_numeric_semver_selector "${_selector}"; then
    _parts="$(semver_selector_part_count "${_selector}")"
    if [ "${_parts}" -eq 1 ] || [ "${_parts}" -eq 2 ]; then
      get_release_metadata_by_semver_selector "${_selector}" "${_target_suffix}"
      return
    fi

    _normalized_tag="${_selector#v}"
    _normalized_tag="${_normalized_tag#V}"
    get_release_metadata "${API_BASE}/releases/tags/v${_normalized_tag}" "${_target_suffix}"
    return
  fi

  get_release_metadata "${API_BASE}/releases/tags/${_selector}" "${_target_suffix}"
}

download_and_verify_package() {
  _pkg_url="${1}"
  _pkg_path="${2}"
  _sha_url="${3}"

  if [ -f "${_pkg_path}" ]; then
    log "Removing existing incomplete download: ${_pkg_path}"
    rm -f "${_pkg_path}"
  fi

  log_info "Downloading to: ${_pkg_path}"
  run curl -fL --retry 3 --retry-delay 2 -C - -o "${_pkg_path}" "${_pkg_url}"

  if [ "${SKIP_CHECKSUM}" -eq 0 ] && [ -n "${_sha_url}" ]; then
    need_cmd sha256sum
    _sha_path="${_pkg_path}.sha256"
    _pkg_name="$(basename "${_pkg_path}")"

    log_info "Downloading checksum file..."
    run curl -fsSL --retry 3 --retry-delay 2 -o "${_sha_path}" "${_sha_url}"

    log_info "Verifying SHA256 checksum..."
    if ! _expected_sha="$(extract_expected_sha256 "${_sha_path}" "${_pkg_name}")"; then
      log_error "ERROR: Could not find a SHA256 entry for ${_pkg_name} in ${_sha_url}"
      exit 1
    fi
    _expected_sha=$(printf '%s' "${_expected_sha}" | tr '[:upper:]' '[:lower:]')
    _actual_sha=$(sha256sum "${_pkg_path}" | awk '{print $1}' | tr '[:upper:]' '[:lower:]')

    if [ "${_expected_sha}" != "${_actual_sha}" ]; then
      log_error "ERROR: SHA256 checksum verification failed!"
      log_error "  Expected: ${_expected_sha}"
      log_error "  Got:      ${_actual_sha}"
      exit 1
    fi
    log_success "SHA256 checksum verified successfully"
    rm -f "${_sha_path}"
  elif [ "${SKIP_CHECKSUM}" -eq 0 ]; then
    log_warn "Warning: SHA256 file not found, skipping checksum verification"
  fi
}

install_package() {
  _pkg_path="${1}"
  _install_version="${2}"
  _install_root="/usr/local/microsoft/powershell"
  _install_path="${_install_root}/${_install_version}"

  run ${SUDO}mkdir -p "${_install_path}"
  log_info "Extracting to: ${_install_path}"
  run ${SUDO}tar -xzf "${_pkg_path}" -C "${_install_path}"
  run ${SUDO}chmod +x "${_install_path}/pwsh"

  log_info "Linking pwsh to /usr/local/bin/pwsh"
  run ${SUDO}ln -sfn "${_install_path}/pwsh" "/usr/local/bin/pwsh"
}

remove_previous_install_version() {
  _previous_version="${1}"
  _target_version="${2}"
  _install_root="/usr/local/microsoft/powershell"
  _previous_path="${_install_root}/${_previous_version}"

  if [ -z "${_previous_version}" ] || [ -z "${_target_version}" ] || [ "${_previous_version}" = "${_target_version}" ]; then
    return 0
  fi

  if [ -d "${_previous_path}" ]; then
    log_info "Removing previous PowerShell version: ${_previous_version}"
    run ${SUDO}rm -rf "${_previous_path}"
  else
    log_warn "Previous PowerShell version directory not found: ${_previous_path}"
  fi
}

check_latest() {
  log_info "Checking network connectivity..."
  check_network

  REL_DATA="$(resolve_release_metadata "" "${TARGET_SUFFIX}")"

  REL_TAG=$(printf '%s\n' "${REL_DATA}" | awk '{print $1}')
  PKG_URL=$(printf '%s\n' "${REL_DATA}" | awk '{print $2}')
  PKG_NAME=$(printf '%s\n' "${REL_DATA}" | awk '{print $3}')

  if [ -z "${PKG_URL}" ]; then
    log_error "ERROR: Could not find a ${TARGET_SUFFIX} asset in the latest release."
    exit 1
  fi

  DESIRED_VERSION="${REL_TAG#v}"
  if [ -z "${DESIRED_VERSION}" ]; then
    log_error "ERROR: Could not determine latest PowerShell release tag."
    exit 1
  fi

  log "Latest PowerShell release: ${REL_TAG}"
  log "Latest package: ${PKG_NAME}"

  INSTALLED_VERSION=""
  if command -v pwsh >/dev/null 2>&1; then
    # shellcheck disable=SC2016
    INSTALLED_VERSION="$(pwsh -NoLogo -NoProfile -Command '$PSVersionTable.PSVersion.ToString()' 2>/dev/null || true)"
  fi

  if [ -z "${INSTALLED_VERSION}" ]; then
    log_warn "PowerShell is not installed."
    log_info "Latest available: ${DESIRED_VERSION}"
    exit 2
  fi

  _cmp=0
  if compare_versions "${INSTALLED_VERSION}" "${DESIRED_VERSION}"; then
    _cmp=0
  else
    _cmp=$?
  fi
  if [ "${_cmp}" -eq 0 ]; then
    log_success "PowerShell ${INSTALLED_VERSION} is up to date (latest: ${DESIRED_VERSION})."
    exit 0
  elif [ "${_cmp}" -eq 1 ]; then
    log_warn "Update available: ${INSTALLED_VERSION} -> ${DESIRED_VERSION}."
    exit 1
  else
    log_warn "Installed version ${INSTALLED_VERSION} is newer than latest release ${DESIRED_VERSION}."
    exit 0
  fi
}

main_install() {
  log_info "Checking network connectivity..."
  check_network

  REL_DATA="$(resolve_release_metadata "${TAG}" "${TARGET_SUFFIX}")"

  REL_TAG=$(printf '%s\n' "${REL_DATA}" | awk '{print $1}')
  PKG_URL=$(printf '%s\n' "${REL_DATA}" | awk '{print $2}')
  PKG_NAME=$(printf '%s\n' "${REL_DATA}" | awk '{print $3}')
  SHA_URL=$(printf '%s\n' "${REL_DATA}" | awk '{print $4}')

  if [ -z "${PKG_URL}" ]; then
    if [ -n "${TAG}" ]; then
      log_error "ERROR: Could not find a ${TARGET_SUFFIX} asset for selector '${TAG}'."
    else
      log_error "ERROR: Could not find a ${TARGET_SUFFIX} asset in the latest release."
    fi
    exit 1
  fi

  log "Selected PowerShell release: ${REL_TAG:-<unknown tag>}"
  log "Selected package: ${PKG_NAME}"
  log "Download URL: ${PKG_URL}"

  DESIRED_VERSION="${REL_TAG#v}"
  INSTALLED_VERSION=""
  VERSION_CMP=0
  UPGRADE_FROM_VERSION=""

  if command -v pwsh >/dev/null 2>&1; then
    # shellcheck disable=SC2016
    INSTALLED_VERSION="$(pwsh -NoLogo -NoProfile -Command '$PSVersionTable.PSVersion.ToString()' 2>/dev/null || true)"
  fi

  if [ -n "${DESIRED_VERSION}" ] && [ -n "${INSTALLED_VERSION}" ]; then
    if compare_versions "${INSTALLED_VERSION}" "${DESIRED_VERSION}"; then
      VERSION_CMP=0
    else
      VERSION_CMP=$?
    fi

    if [ "${VERSION_CMP}" -eq 1 ]; then
      UPGRADE_FROM_VERSION="${INSTALLED_VERSION}"
    fi
  fi

  if [ "${DRY_RUN}" -eq 1 ]; then
    log "Dry-run summary:"
    log "  Would download: ${PKG_URL}"
    log "  Would install : ${PKG_NAME}"
    log "  Target arch   : ${PKG_ARCH} (musl=${MUSL})"
    log "  Would verify  : SHA256 checksum"
    log "  Would install to /usr/local/microsoft/powershell/<version>"
    if [ -n "${UPGRADE_FROM_VERSION}" ]; then
      if [ "${KEEP_OLD_VERSION}" -eq 1 ]; then
        log "  Would keep    : previous version ${UPGRADE_FROM_VERSION}"
      else
        log "  Would remove  : previous version ${UPGRADE_FROM_VERSION} after successful upgrade"
      fi
    fi
    trap - EXIT INT TERM
    exit 0
  fi

  if [ "${FORCE}" -eq 0 ] && [ -n "${DESIRED_VERSION}" ] && [ -n "${INSTALLED_VERSION}" ] && [ "${VERSION_CMP}" -eq 0 ]; then
    log_warn "PowerShell ${INSTALLED_VERSION} is already installed; use --force to reinstall."
    exit 0
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

  install_package "${PKG_PATH}" "${DESIRED_VERSION}"

  if [ -n "${UPGRADE_FROM_VERSION}" ]; then
    if [ "${KEEP_OLD_VERSION}" -eq 1 ]; then
      log_info "Keeping previous PowerShell version: ${UPGRADE_FROM_VERSION}"
    else
      remove_previous_install_version "${UPGRADE_FROM_VERSION}" "${DESIRED_VERSION}"
    fi
  fi

  if [ "${KEEP}" -eq 1 ] || [ -n "${OUT_DIR}" ]; then
    log "Keeping tarball at: ${PKG_PATH}"
  else
    if [ -n "${TMP_DIR}" ]; then
      log_info "Cleaning up temporary files..."
      rm -rf "${TMP_DIR}"
      TMP_DIR=""
    fi
  fi

  trap - EXIT INT TERM
  log_success "Done. Verify with: pwsh -v"
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
  --keep-old-version)
    KEEP_OLD_VERSION=1
    shift
    ;;
  --check)
    CHECK_ONLY=1
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
    log_error "Unknown argument: ${1}"
    usage
    exit 1
    ;;
  esac
done

if [ "${CHECK_ONLY}" -eq 1 ]; then
  if [ -n "${TAG}" ] || [ -n "${OUT_DIR}" ] || [ "${KEEP}" -eq 1 ] || [ "${FORCE}" -eq 1 ] || [ "${KEEP_OLD_VERSION}" -eq 1 ] || [ "${UNINSTALL}" -eq 1 ] || [ "${SKIP_CHECKSUM}" -eq 1 ]; then
    log_error "ERROR: --check cannot be combined with install/uninstall options."
    exit 1
  fi
fi

SUDO=""
if [ "${CHECK_ONLY}" -eq 0 ]; then
  if [ "$(id -u)" -ne 0 ]; then
    if command -v sudo >/dev/null 2>&1; then
      SUDO="sudo"
    else
      if [ "${DRY_RUN}" -eq 1 ]; then
        SUDO="sudo"
      else
        log_error "ERROR: this script needs root privileges (installing to /usr/local). Please run as root or install sudo."
        exit 1
      fi
    fi
  fi
fi

need_cmd uname

if [ "${UNINSTALL}" -eq 0 ]; then
  need_cmd curl
fi

if [ "${UNINSTALL}" -eq 0 ] && [ "${CHECK_ONLY}" -eq 0 ]; then
  need_cmd tar
fi

if [ "${UNINSTALL}" -eq 1 ]; then
  trap - EXIT INT TERM
  INSTALL_ROOT="/usr/local/microsoft/powershell"
  if [ -d "${INSTALL_ROOT}" ]; then
    log "Removing ${INSTALL_ROOT}"
    run ${SUDO}rm -rf "${INSTALL_ROOT}"
  else
    log_warn "No PowerShell install found at ${INSTALL_ROOT}"
  fi
  if [ -L "/usr/local/bin/pwsh" ]; then
    log "Removing /usr/local/bin/pwsh"
    run ${SUDO}rm -f "/usr/local/bin/pwsh"
  fi
  log_success "Uninstall complete."

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
    log_warn "Note: The following user-specific directories still exist and may be removed manually:"
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
  log_error "ERROR: Unsupported architecture: ${ARCH} (expected x86_64 or arm64)."
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
  log_error "ERROR: python3 (or python) is required to parse GitHub release JSON."

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

if [ "${CHECK_ONLY}" -eq 1 ]; then
  if [ "${DRY_RUN}" -eq 1 ]; then
    log "Dry-run summary:"
    log "  Would check latest PowerShell release for ${TARGET_SUFFIX}"
    log "  Would compare against installed pwsh version (if present)"
    trap - EXIT INT TERM
    exit 0
  fi
  check_latest
fi

main_install
