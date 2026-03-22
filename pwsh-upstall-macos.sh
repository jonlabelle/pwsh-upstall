#!/usr/bin/env bash
set -euo pipefail

# pwsh-upstall-macos.sh
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
#   ./pwsh-upstall-macos.sh [options]
#
#   Options:
#     --tag <tag>        Select release by semver/tag:
#                        - v7      => latest 7.x.x (major track)
#                        - v7.5    => latest 7.5.x (minor track)
#                        - v7.5.4  => specific patch release
#                        - other tags (e.g., preview) are resolved exactly
#                        Prereleases are supported only via explicit exact tag;
#                        default/latest/major/minor selection is stable-only.
#     --out-dir <dir>    Save downloaded package to specified directory
#     --keep             Retain package after installation
#     --force            Reinstall even if target version already installed
#     --keep-old-version Preserve the previously installed version when upgrading
#     --check            Only check if installed version is up to date
#     --uninstall        Remove PowerShell and associated package receipts
#     --skip-checksum    Skip SHA256 verification (not recommended)
#     -n, --dry-run      Preview actions without making changes
#     -h, --help         Display usage information
#
# EXAMPLES:
#   # Install latest stable release
#   ./pwsh-upstall-macos.sh
#
#   # Install latest 7.x release
#   ./pwsh-upstall-macos.sh --tag v7
#
#   # Install latest 7.5.x release
#   ./pwsh-upstall-macos.sh --tag v7.5
#
#   # Install specific patch version
#   ./pwsh-upstall-macos.sh --tag v7.5.4
#
#   # Download to ~/Downloads and keep package
#   ./pwsh-upstall-macos.sh --out-dir "$HOME/Downloads" --keep
#
#   # Check if PowerShell is up to date
#   ./pwsh-upstall-macos.sh --check
#
#   # Uninstall PowerShell
#   ./pwsh-upstall-macos.sh --uninstall
#
# NOTES:
#   - Installs to /usr/local/microsoft/powershell/<version>
#   - Creates symlink at /usr/local/bin/pwsh
#   - Automatically detects architecture (arm64 or x64)
#   - Verifies Microsoft code signature and SHA256 checksums
#   - Validates disk space before installation
#   - Removes the previously active version after a successful upgrade
#     unless --keep-old-version is used
#   - Default behavior downloads latest stable release (not preview/RC)
#   - Prereleases are supported only via explicit exact tag
#     (default/latest/major/minor selection is stable-only)
#
# Author: Jon LaBelle
# Source: https://github.com/jonlabelle/pwsh-upstall/blob/main/pwsh-upstall-macos.sh

API_BASE="https://api.github.com/repos/PowerShell/PowerShell"

DRY_RUN=0
TAG="" # e.g., v7.5.4
KEEP=0
OUT_DIR="" # optional destination directory for the downloaded pkg
FORCE=0
KEEP_OLD_VERSION=0
UNINSTALL=0
SKIP_CHECKSUM=0
CHECK_ONLY=0
TMP_DIR=""

# ANSI colors (disabled when not on a TTY or NO_COLOR is set)
if [[ -t 1 && -z "${NO_COLOR:-}" ]]; then
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
  if [[ -n "${TMP_DIR}" && -d "${TMP_DIR}" ]]; then
    log "Cleaning up temporary files due to error..."
    rm -rf "${TMP_DIR}" 2>/dev/null || true
  fi
}

trap cleanup_on_error EXIT INT TERM

usage() {
  cat <<'USAGE'
Usage:
  pwsh-upstall-macos.sh [options]

Options:
  --tag <tag>        Select release by semver/tag:
                     - v7      => latest 7.x.x (major track)
                     - v7.5    => latest 7.5.x (minor track)
                     - v7.5.4  => specific patch release
                     - other tags (e.g., preview) are resolved exactly
                     If omitted (or set to 'latest'), installs the latest stable release.
                     Prereleases are supported only via explicit exact tag.
  --out-dir <dir>    Directory to save the downloaded .pkg (default: temp dir).
  --keep             Keep the downloaded .pkg after installation (default: delete unless --out-dir is used).
  --force            Reinstall even if the target version is already installed.
  --keep-old-version Keep the previously installed version when upgrading.
  --check            Only check if installed version is up to date; no download or install.
  --uninstall        Uninstall PowerShell from the default install location.
  --skip-checksum    Skip SHA256 checksum verification (not recommended).
  -n, --dry-run      Show what would happen, but do not download or install.
  -h, --help         Show help.

Examples:
  # Install latest stable PowerShell
  ./pwsh-upstall-macos.sh

  # Install latest release in major line 7.x
  ./pwsh-upstall-macos.sh --tag v7

  # Install latest release in minor line 7.5.x
  ./pwsh-upstall-macos.sh --tag v7.5

  # Install a specific patch version
  ./pwsh-upstall-macos.sh --tag v7.5.4

  # Download to ~/Downloads and keep the package
  ./pwsh-upstall-macos.sh --out-dir "$HOME/Downloads" --keep

  # Preview actions only
  ./pwsh-upstall-macos.sh --dry-run

  # Check if PowerShell is up to date
  ./pwsh-upstall-macos.sh --check

  # Reinstall even if already on the target version
  ./pwsh-upstall-macos.sh --force

  # Uninstall PowerShell
  ./pwsh-upstall-macos.sh --uninstall
USAGE
}

log() { printf '%s\n' "$*"; }
log_info() { printf '%s\n' "${C_CYAN}$*${C_RESET}"; }
log_warn() { printf '%s\n' "${C_YELLOW}$*${C_RESET}"; }
log_success() { printf '%s\n' "${C_GREEN}$*${C_RESET}"; }
log_error() { printf '%s\n' "${C_RED}$*${C_RESET}" >&2; }
run() {
  if [[ "${DRY_RUN}" -eq 1 ]]; then
    log "[dry-run] $*"
  else
    "$@"
  fi
}

need_cmd() {
  command -v "$1" >/dev/null 2>&1 || {
    log_error "ERROR: missing required command: $1"

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

  local status=""
  if [[ -n "${GITHUB_TOKEN:-}" ]]; then
    status="$(curl -sSL --connect-timeout 5 --max-time 10 -o /dev/null -w "%{http_code}" -H "Authorization: Bearer ${GITHUB_TOKEN}" "https://api.github.com" 2>/dev/null || true)"
  else
    status="$(curl -sSL --connect-timeout 5 --max-time 10 -o /dev/null -w "%{http_code}" "https://api.github.com" 2>/dev/null || true)"
  fi

  if [[ -z "${status}" || "${status}" == "000" || "${status}" -ge 500 ]]; then
    log_error "ERROR: Cannot reach GitHub API. Check your internet connection."
    exit 1
  fi
}

check_disk_space() {
  local target_dir="${1}"
  local required_mb="${2:-500}"

  if ! command -v df >/dev/null 2>&1; then
    log_warn "Warning: 'df' command not found, skipping disk space check"
    return 0
  fi

  local available_kb
  available_kb=$(df -k "${target_dir}" 2>/dev/null | awk 'NR==2 {print $4}')

  if [[ -z "${available_kb}" ]]; then
    log_warn "Warning: Could not determine available disk space"
    return 0
  fi

  local available_mb=$((available_kb / 1024))

  if [[ "${available_mb}" -lt "${required_mb}" ]]; then
    log_error "ERROR: Insufficient disk space. Required: ${required_mb}MB, Available: ${available_mb}MB"
    exit 1
  fi

  log_success "Disk space check passed: ${available_mb}MB available"
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

extract_expected_sha256() {
  local checksum_path="${1}"
  local asset_name="${2}"

  "${PYTHON}" - "${checksum_path}" "${asset_name}" <<'PY'
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
hashes_url = ""
for a in assets:
  name = a.get("name") or ""
  url  = a.get("browser_download_url") or ""
  if name == "hashes.sha256":
    hashes_url = url
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
  if not sha_url:
    sha_url = hashes_url
  print(tag, url, name, sha_url)
PY
}

github_api_get() {
  local url="${1}"
  if [[ -n "${GITHUB_TOKEN:-}" ]]; then
    curl -fsSL --retry 3 --retry-delay 2 -H "Authorization: Bearer ${GITHUB_TOKEN}" "${url}"
  else
    curl -fsSL --retry 3 --retry-delay 2 "${url}"
  fi
}

is_numeric_semver_selector() {
  local selector="${1}"
  [[ "${selector}" =~ ^[vV]?[0-9]+(\.[0-9]+){0,2}$ ]]
}

semver_selector_part_count() {
  local selector="${1#v}"
  selector="${selector#V}"
  awk -F'.' '{print NF}' <<<"${selector}"
}

get_release_metadata_by_semver_selector() {
  local selector="${1}"
  local target_pkg_suffix="${2}"
  local selector_no_v="${selector#v}"
  selector_no_v="${selector_no_v#V}"

  log "Resolving semver selector: ${selector}" >&2

  local json_file
  json_file="$(mktemp)"
  github_api_get "${API_BASE}/releases?per_page=100" >"${json_file}"

  "${PYTHON}" - "${json_file}" "${target_pkg_suffix}" "${selector_no_v}" <<'PY'
import json, re, sys

with open(sys.argv[1], "r", encoding="utf-8") as f:
  releases = json.load(f)
target_suffix = sys.argv[2]
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
  hashes_url = ""
  for asset in assets:
    name = asset.get("name") or ""
    url = asset.get("browser_download_url") or ""
    if name == "hashes.sha256":
      hashes_url = url
    if target_suffix in name and name.endswith(".pkg"):
      candidates.append((name, url))

  def score(item):
    name, _ = item
    s = 0
    lname = name.lower()
    if "preview" in lname:
      s -= 10
    if "rc" in lname:
      s -= 5
    if re.match(rf"^powershell-.*-{re.escape(target_suffix)}$", name):
      s += 5
    return s

  candidates.sort(key=score, reverse=True)
  if not candidates:
    return None

  name, url = candidates[0]
  sha_name = name + ".sha256"
  sha_url = ""
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
  rm -f "${json_file}"
}

resolve_release_metadata() {
  local selector="${1:-}"
  local target_pkg_suffix="${2}"
  local selector_lc
  selector_lc="$(tr '[:upper:]' '[:lower:]' <<<"${selector}")"

  if [[ -z "${selector}" || "${selector_lc}" == "latest" ]]; then
    get_release_metadata "${API_BASE}/releases/latest" "${target_pkg_suffix}"
    return
  fi

  if is_numeric_semver_selector "${selector}"; then
    local parts
    parts="$(semver_selector_part_count "${selector}")"
    if [[ "${parts}" -eq 1 || "${parts}" -eq 2 ]]; then
      get_release_metadata_by_semver_selector "${selector}" "${target_pkg_suffix}"
      return
    fi

    local normalized_tag="${selector#v}"
    normalized_tag="${normalized_tag#V}"
    get_release_metadata "${API_BASE}/releases/tags/v${normalized_tag}" "${target_pkg_suffix}"
    return
  fi

  get_release_metadata "${API_BASE}/releases/tags/${selector}" "${target_pkg_suffix}"
}

download_and_verify_package() {
  local pkg_url="${1}"
  local pkg_path="${2}"
  local sha_url="${3}"

  if [[ -f "${pkg_path}" ]]; then
    log "Removing existing incomplete download: ${pkg_path}"
    rm -f "${pkg_path}"
  fi

  log_info "Downloading to: ${pkg_path}"
  run curl -fL --retry 3 --retry-delay 2 -C - -o "${pkg_path}" "${pkg_url}"

  # Verify SHA256 checksum
  if [[ "${SKIP_CHECKSUM}" -eq 0 && -n "${sha_url}" ]]; then
    need_cmd shasum
    local sha_path="${pkg_path}.sha256"
    local pkg_name
    pkg_name="$(basename "${pkg_path}")"

    log_info "Downloading checksum file..."
    run curl -fsSL --retry 3 --retry-delay 2 -o "${sha_path}" "${sha_url}"

    log_info "Verifying SHA256 checksum..."
    local expected_sha actual_sha
    if ! expected_sha="$(extract_expected_sha256 "${sha_path}" "${pkg_name}")"; then
      log_error "ERROR: Could not find a SHA256 entry for ${pkg_name} in ${sha_url}"
      exit 1
    fi
    expected_sha="$(printf '%s' "${expected_sha}" | tr '[:upper:]' '[:lower:]')"
    actual_sha="$(shasum -a 256 "${pkg_path}" | awk '{print $1}' | tr '[:upper:]' '[:lower:]')"

    if [[ "${expected_sha}" != "${actual_sha}" ]]; then
      log_error "ERROR: SHA256 checksum verification failed!"
      log_error "  Expected: ${expected_sha}"
      log_error "  Got:      ${actual_sha}"
      exit 1
    fi
    log_success "SHA256 checksum verified successfully"
    rm -f "${sha_path}"
  elif [[ "${SKIP_CHECKSUM}" -eq 0 ]]; then
    log_warn "Warning: SHA256 file not found, skipping checksum verification"
  fi

  # Verify Microsoft signature
  log_info "Checking package signature..."
  run pkgutil --check-signature "${pkg_path}"
  if [[ "${DRY_RUN}" -eq 0 ]]; then
    verify_microsoft_signature "${pkg_path}" || log_warn "Warning: Could not verify Microsoft signature"
  fi
}

install_package() {
  local pkg_path="${1}"

  log_info "Installing PowerShell (requires sudo)…"
  run sudo installer -pkg "${pkg_path}" -target /

  # Verify
  log_info "Verifying installation…"
  run command -v pwsh
  # shellcheck disable=SC2016
  run pwsh -NoLogo -NoProfile -Command '$PSVersionTable.PSVersion'
}

remove_previous_install_version() {
  local previous_version="${1}"
  local target_version="${2}"
  local target_root="/usr/local/microsoft/powershell"
  local previous_path="${target_root}/${previous_version}"

  if [[ -z "${previous_version}" || -z "${target_version}" || "${previous_version}" == "${target_version}" ]]; then
    return 0
  fi

  if [[ -d "${previous_path}" ]]; then
    log_info "Removing previous PowerShell version: ${previous_version}"
    run sudo rm -rf "${previous_path}"
  else
    log_warn "Previous PowerShell version directory not found: ${previous_path}"
  fi
}

check_latest() {
  log_info "Checking network connectivity..."
  check_network

  local target_pkg_suffix="osx-${PKG_ARCH}.pkg"
  local rel_tag pkg_url pkg_name sha_url
  read -r rel_tag pkg_url pkg_name sha_url < <(resolve_release_metadata "" "${target_pkg_suffix}")

  if [[ -z "${pkg_url}" ]]; then
    log_error "ERROR: Could not find an ${target_pkg_suffix} asset in the latest release."
    exit 1
  fi

  local desired_version="${rel_tag#v}"
  if [[ -z "${desired_version}" ]]; then
    log_error "ERROR: Could not determine latest PowerShell release tag."
    exit 1
  fi

  log "Latest PowerShell release: ${rel_tag}"
  log "Latest package: ${pkg_name}"

  local installed_version=""
  if command -v pwsh >/dev/null 2>&1; then
    # shellcheck disable=SC2016
    installed_version="$(pwsh -NoLogo -NoProfile -Command '$PSVersionTable.PSVersion.ToString()' 2>/dev/null || true)"
  fi

  if [[ -z "${installed_version}" ]]; then
    log_warn "PowerShell is not installed."
    log_info "Latest available: ${desired_version}"
    exit 2
  fi

  local version_cmp=0
  if compare_versions "${installed_version}" "${desired_version}"; then
    :
  else
    version_cmp=$?
  fi
  if [[ ${version_cmp} -eq 0 ]]; then
    log_success "PowerShell ${installed_version} is up to date (latest: ${desired_version})."
    exit 0
  elif [[ ${version_cmp} -eq 1 ]]; then
    log_warn "Update available: ${installed_version} -> ${desired_version}."
    exit 1
  else
    log_warn "Installed version ${installed_version} is newer than latest release ${desired_version}."
    exit 0
  fi
}

main_install() {
  log_info "Checking network connectivity..."
  check_network

  local target_pkg_suffix="osx-${PKG_ARCH}.pkg"
  local rel_tag pkg_url pkg_name sha_url
  read -r rel_tag pkg_url pkg_name sha_url < <(resolve_release_metadata "${TAG}" "${target_pkg_suffix}")

  if [[ -z "${pkg_url}" ]]; then
    if [[ -n "${TAG}" ]]; then
      log_error "ERROR: Could not find an ${target_pkg_suffix} asset for selector '${TAG}'."
      log_error "Tip: Try --tag v7, --tag v7.5, --tag v7.5.4, or a full release tag."
    else
      log_error "ERROR: Could not find an ${target_pkg_suffix} asset in the latest release."
    fi
    exit 1
  fi

  log "Selected PowerShell release: ${rel_tag:-<unknown tag>}"
  log "Selected package: ${pkg_name}"
  log "Download URL: ${pkg_url}"

  local desired_version="${rel_tag#v}"
  local installed_version=""
  local version_cmp=0
  local upgrade_from_version=""

  if command -v pwsh >/dev/null 2>&1; then
    # shellcheck disable=SC2016
    installed_version="$(pwsh -NoLogo -NoProfile -Command '$PSVersionTable.PSVersion.ToString()' 2>/dev/null || true)"
  fi

  if [[ -n "${desired_version}" && -n "${installed_version}" ]]; then
    if compare_versions "${installed_version}" "${desired_version}"; then
      version_cmp=0
    else
      version_cmp=$?
    fi

    if [[ ${version_cmp} -eq 1 ]]; then
      upgrade_from_version="${installed_version}"
    fi
  fi

  if [[ "${DRY_RUN}" -eq 1 ]]; then
    log "Dry-run summary:"
    log "  Would download: ${pkg_url}"
    log "  Would install : ${pkg_name}"
    log "  Would verify  : SHA256 checksum & Microsoft signature"
    log "  Would run     : sudo installer -pkg <downloaded-pkg> -target /"
    if [[ -n "${upgrade_from_version}" ]]; then
      if [[ "${KEEP_OLD_VERSION}" -eq 1 ]]; then
        log "  Would keep    : previous version ${upgrade_from_version}"
      else
        log "  Would remove  : previous version ${upgrade_from_version} after successful upgrade"
      fi
    fi
    trap - EXIT TERM
    exit 0
  fi

  if [[ "${FORCE}" -eq 0 ]]; then
    if [[ -n "${desired_version}" && -n "${installed_version}" && ${version_cmp} -eq 0 ]]; then
      log_warn "PowerShell ${installed_version} is already installed; skipping install. Use --force to reinstall."
      trap - EXIT INT TERM
      exit 0
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

  if [[ -n "${upgrade_from_version}" ]]; then
    if [[ "${KEEP_OLD_VERSION}" -eq 1 ]]; then
      log_info "Keeping previous PowerShell version: ${upgrade_from_version}"
    else
      remove_previous_install_version "${upgrade_from_version}" "${desired_version}"
    fi
  fi

  # Cleanup
  if [[ "${KEEP}" -eq 1 || -n "${OUT_DIR}" ]]; then
    log "Keeping package at: ${pkg_path}"
  else
    if [[ -n "${TMP_DIR}" ]]; then
      log_info "Cleaning up temporary files…"
      run rm -rf "${TMP_DIR}"
      TMP_DIR=""
    fi
  fi

  trap - EXIT INT TERM
  log_success "Done."
}

verify_microsoft_signature() {
  local pkg_path="${1}"

  log_info "Verifying package signature..."
  if ! pkgutil --check-signature "${pkg_path}" 2>&1 | grep -q "Developer ID Installer: Microsoft Corporation"; then
    log_warn "Warning: Package does not appear to be signed by Microsoft Corporation"
    log_warn "Signature details:"
    pkgutil --check-signature "${pkg_path}" 2>&1 || true
    return 1
  fi

  log_success "Package signature verified: Microsoft Corporation"
  return 0
}

uninstall_pwsh() {
  local target_root="/usr/local/microsoft/powershell"
  local pwsh_link="/usr/local/bin/pwsh"
  local removed_any=0

  if [[ -d "${target_root}" ]]; then
    log_info "Uninstalling PowerShell from: ${target_root}"
    run sudo rm -rf "${target_root}"
    removed_any=1
  else
    log_warn "No PowerShell install found at: ${target_root}"
  fi

  if [[ -L "${pwsh_link}" ]]; then
    local link_target=""
    link_target="$(readlink "${pwsh_link}" 2>/dev/null || true)"
    if [[ "${link_target}" == *"microsoft/powershell/"* ]]; then
      log_info "Removing symlink: ${pwsh_link}"
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
        log_info "Forgetting package receipt: ${pkg}"
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
    log_success "Uninstall complete."
  else
    log_warn "Nothing to uninstall."
  fi

  # Check for user-specific directories that may need manual cleanup
  local user_dirs=()
  [[ -d "${HOME}/.config/powershell" ]] && user_dirs+=("${HOME}/.config/powershell")
  [[ -d "${HOME}/.local/share/powershell" ]] && user_dirs+=("${HOME}/.local/share/powershell")
  [[ -d "${HOME}/.cache/powershell" ]] && user_dirs+=("${HOME}/.cache/powershell")

  if [[ "${#user_dirs[@]}" -gt 0 ]]; then
    log ""
    log_warn "Note: The following user-specific directories still exist and may be removed manually:"
    for dir in "${user_dirs[@]}"; do
      log_warn "  ${dir}"
    done
    log_warn "To remove them, run: rm -rf ~/.config/powershell ~/.local/share/powershell ~/.cache/powershell"
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
    log_error "Unknown argument: $1"
    usage
    exit 1
    ;;
  esac
done

if [[ "${CHECK_ONLY}" -eq 1 ]]; then
  if [[ -n "${TAG}" || -n "${OUT_DIR}" || "${KEEP}" -eq 1 || "${FORCE}" -eq 1 || "${KEEP_OLD_VERSION}" -eq 1 || "${UNINSTALL}" -eq 1 || "${SKIP_CHECKSUM}" -eq 1 ]]; then
    log_error "ERROR: --check cannot be combined with install/uninstall options."
    exit 1
  fi
fi

need_cmd uname

if [[ "${UNINSTALL}" -eq 0 ]]; then
  need_cmd curl
  if [[ "${CHECK_ONLY}" -eq 0 ]]; then
    need_cmd pkgutil
    need_cmd installer
  fi
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
  log_error "ERROR: Unsupported architecture: ${ARCH} (expected arm64 or x86_64)."
  exit 1
  ;;
esac

log_info "Detected architecture: ${ARCH} -> selecting macOS ${PKG_ARCH} package"

PYTHON=""
if command -v python3 >/dev/null 2>&1; then
  PYTHON="python3"
elif command -v python >/dev/null 2>&1; then
  PYTHON="python"
else
  log_error "ERROR: python3 (or python) is required to parse GitHub release JSON."

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

if [[ "${CHECK_ONLY}" -eq 1 ]]; then
  if [[ "${DRY_RUN}" -eq 1 ]]; then
    log "Dry-run summary:"
    log "  Would check latest PowerShell release for osx-${PKG_ARCH}.pkg"
    log "  Would compare against installed pwsh version (if present)"
    trap - EXIT INT TERM
    exit 0
  fi
  check_latest
fi

main_install
