#!/usr/bin/env bash
#
# trim-screenshot.sh - Trim transparent padding from macOS terminal screenshots
#
# Removes excess transparent space from the top and bottom of PNG screenshots
# while preserving the shadow effect. Designed for screenshots taken with
# macOS screenshot tools that add shadow/padding.
#
# Used to trim my macOS Terminal screenshots for the pwsh-project project:
# https://github.com/jonlabelle/pwsh-profile
#
# Dependencies:
# - ImageMagick (brew install imagemagick)
#
# Snippet:
# https://jonlabelle.com/snippets/view/shell/trim-excess-space-from-screenshot
#
# Author: Jon LaBelle
# License: MIT
# Date: 2026-01-30
#

set -euo pipefail

# Default values
TOP_TRIM=40
BOTTOM_TRIM=50
OUTPUT_DIR=""
SUFFIX=""
BACKUP=false
FORCE=false
DRY_RUN=false

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

usage() {
  cat <<'EOF'
trim-screenshot.sh - Trim transparent padding from macOS terminal screenshots

Removes excess transparent space from the top and bottom of PNG screenshots
while preserving the shadow effect. Designed for screenshots taken with
macOS screenshot tools that add shadow/padding.

Usage:
  ./trim-screenshot.sh <image.png> [image2.png ...]
  ./trim-screenshot.sh -t 40 -b 50 screenshot.png
  ./trim-screenshot.sh --top 30 --bottom 40 *.png

Options:
  -t, --top <pixels>     Pixels to trim from top (default: 40)
  -b, --bottom <pixels>  Pixels to trim from bottom (default: 50)
  -o, --output <path>    Output path: directory for multiple files, or filename for single file
  -s, --suffix <suffix>  Add suffix to output filename (e.g., '-trimmed')
  -k, --keep-backup      Create backup of original file (.bak extension)
  -f, --force            Overwrite existing output files without prompting
  -n, --dry-run          Show what would be done without making changes
  -h, --help             Show this help message

Requirements:
  - ImageMagick (brew install imagemagick)

Examples:
  # Trim with defaults (40px top, 50px bottom)
  ./trim-screenshot.sh screenshot.png

  # Trim multiple images
  ./trim-screenshot.sh term-screen-shot.png netdiag.png

  # Custom trim amounts
  ./trim-screenshot.sh -t 30 -b 60 screenshot.png

  # Output to different directory with suffix
  ./trim-screenshot.sh -o ./trimmed -s '-small' *.png

  # Output to specific filename (single file only)
  ./trim-screenshot.sh -o result.png screenshot.png

  # Preview changes without modifying files
  ./trim-screenshot.sh --dry-run *.png
EOF
  exit 0
}

error() {
  echo -e "${RED}Error:${NC} $1" >&2
  exit 1
}

info() {
  echo -e "${BLUE}→${NC} $1"
}

success() {
  echo -e "${GREEN}✓${NC} $1"
}

warn() {
  echo -e "${YELLOW}⚠${NC} $1"
}

# Check for ImageMagick
check_dependencies() {
  if ! command -v magick &>/dev/null; then
    error "ImageMagick is required but not installed. Install with: brew install imagemagick"
  fi
}

# Trim a single image
trim_image() {
  local input="$1"
  local filename
  local base
  local ext
  local output

  # Validate input file
  if [[ ! -f "${input}" ]]; then
    warn "File not found: ${input}"
    return 1
  fi

  # Check if it's a PNG (case-insensitive)
  local lower_input
  lower_input=$(echo "${input}" | tr '[:upper:]' '[:lower:]')
  if [[ "${lower_input}" != *.png ]]; then
    warn "Skipping non-PNG file: ${input}"
    return 1
  fi

  filename=$(basename "${input}")
  base="${filename%.*}"
  ext="${filename##*.}"

  # Determine output path
  if [[ -n "${OUTPUT_DIR}" ]]; then
    # Check if OUTPUT_DIR is an existing directory or looks like a directory path
    if [[ -d "${OUTPUT_DIR}" ]] || [[ "${OUTPUT_DIR}" == */ ]]; then
      # It's a directory - use original filename (with optional suffix)
      output="${OUTPUT_DIR%/}/${base}${SUFFIX}.${ext}"
    else
      # It's a file path - use it directly (suffix is ignored)
      output="${OUTPUT_DIR}"
    fi
  elif [[ -n "${SUFFIX}" ]]; then
    local dir
    dir=$(dirname "${input}")
    output="${dir}/${base}${SUFFIX}.${ext}"
  else
    output="${input}"
  fi

  # Get original dimensions
  local orig_height
  local orig_width
  orig_height=$(magick identify -format '%h' "${input}")
  orig_width=$(magick identify -format '%w' "${input}")

  # Calculate new height
  local new_height=$((orig_height - TOP_TRIM - BOTTOM_TRIM))

  if [[ ${new_height} -le 0 ]]; then
    warn "Trim values (${TOP_TRIM} + ${BOTTOM_TRIM}) exceed image height (${orig_height}): ${input}"
    return 1
  fi

  if [[ "${DRY_RUN}" == true ]]; then
    info "[dry-run] Would trim '${input}'"
    echo "    Original: ${orig_width}x${orig_height}"
    echo "    New:      ${orig_width}x${new_height} (top: -${TOP_TRIM}px, bottom: -${BOTTOM_TRIM}px)"
    echo "    Output:   ${output}"
    return 0
  fi

  # Check if output file exists and we're not forcing overwrite
  # (skip check if output is the same as input - that's in-place modification)
  if [[ -f "${output}" ]] && [[ "${output}" != "${input}" ]] && [[ "${FORCE}" == false ]]; then
    warn "Output file already exists: ${output} (use --force to overwrite)"
    return 1
  fi

  # Create backup if requested
  if [[ "${BACKUP}" == true ]] && [[ "${output}" == "${input}" ]]; then
    local backup_file="${input}.bak"
    cp "${input}" "${backup_file}"
    info "Backup saved: ${backup_file}"
  fi

  # Perform the trim (preserving PNG quality and color settings)
  info "Trimming '${input}'..."

  # PNG quality options to preserve original characteristics
  local png_opts=(
    -quality 95                              # Compression level 9, adaptive filtering
    -define png:compression-filter=adaptive  # Best filter selection
    -define png:compression-level=9          # Maximum compression
    -define png:compression-strategy=default # Standard strategy
    -define png:exclude-chunk=date           # Don't update date chunk
  )

  if [[ "${output}" == "${input}" ]]; then
    # In-place modification - use temp file
    local temp_file
    temp_file=$(mktemp "${TMPDIR:-/tmp}/trim-screenshot.XXXXXX.png")
    magick "${input}" -gravity North -chop "0x${TOP_TRIM}" -gravity South -chop "0x${BOTTOM_TRIM}" "${png_opts[@]}" "${temp_file}"
    mv "${temp_file}" "${output}"
  else
    magick "${input}" -gravity North -chop "0x${TOP_TRIM}" -gravity South -chop "0x${BOTTOM_TRIM}" "${png_opts[@]}" "${output}"
  fi

  success "Saved: ${output} (${orig_width}x${orig_height} → ${orig_width}x${new_height})"
}

main() {
  local files=()

  # Parse command line arguments
  while [[ $# -gt 0 ]]; do
    case $1 in
    -t | --top)
      TOP_TRIM="$2"
      shift 2
      ;;
    -b | --bottom)
      BOTTOM_TRIM="$2"
      shift 2
      ;;
    -o | --output)
      OUTPUT_DIR="$2"
      shift 2
      ;;
    -s | --suffix)
      SUFFIX="$2"
      shift 2
      ;;
    -k | --keep-backup)
      BACKUP=true
      shift
      ;;
    -f | --force)
      FORCE=true
      shift
      ;;
    -n | --dry-run)
      DRY_RUN=true
      shift
      ;;
    -h | --help)
      usage
      ;;
    -*)
      error "Unknown option: $1"
      ;;
    *)
      files+=("$1")
      shift
      ;;
    esac
  done

  # Validate we have files
  if [[ ${#files[@]} -eq 0 ]]; then
    error "No input files specified. Use -h for help."
  fi

  # Validate numeric inputs
  if ! [[ "${TOP_TRIM}" =~ ^[0-9]+$ ]]; then
    error "Top trim must be a positive integer: ${TOP_TRIM}"
  fi
  if ! [[ "${BOTTOM_TRIM}" =~ ^[0-9]+$ ]]; then
    error "Bottom trim must be a positive integer: ${BOTTOM_TRIM}"
  fi

  check_dependencies

  # Create output directory if specified and it's a directory path
  if [[ -n "${OUTPUT_DIR}" ]] && [[ "${DRY_RUN}" == false ]]; then
    if [[ -d "${OUTPUT_DIR}" ]] || [[ "${OUTPUT_DIR}" == */ ]]; then
      mkdir -p "${OUTPUT_DIR%/}"
    else
      # It's a file path - create parent directory if needed
      local parent_dir
      parent_dir=$(dirname "${OUTPUT_DIR}")
      [[ -n "${parent_dir}" ]] && [[ "${parent_dir}" != "." ]] && mkdir -p "${parent_dir}"
    fi
  fi

  echo ""
  if [[ "${DRY_RUN}" == true ]]; then
    warn "Dry run mode - no files will be modified"
  fi
  info "Trim settings: top=${TOP_TRIM}px, bottom=${BOTTOM_TRIM}px"
  echo ""

  local count=0
  local failed=0

  for file in "${files[@]}"; do
    # shellcheck disable=SC2310  # Function has explicit error handling, doesn't rely on set -e
    if trim_image "${file}"; then
      ((count++)) || true
    else
      ((failed++)) || true
    fi
  done

  echo ""
  if [[ "${DRY_RUN}" == true ]]; then
    info "Dry run complete. Would process ${count} file(s)."
  else
    success "Processed ${count} file(s) successfully."
  fi

  if [[ ${failed} -gt 0 ]]; then
    warn "${failed} file(s) skipped or failed."
  fi
}

main "$@"
