#!/usr/bin/env bash
set -euo pipefail

U64_IP="${U64_IP:-10.0.0.79}"
VPL_NAME="${VPL_NAME:-SEPIA.VPL}"
VPL_FILE="${VPL_FILE:-./SEPIA.VPL}"
FTP_USER="${FTP_USER:-anonymous}"
FTP_PASS="${FTP_PASS:-anonymous@}"
SAVE_TO_FLASH="${SAVE_TO_FLASH:-0}"
SKIP_UPLOAD="${SKIP_UPLOAD:-0}"

api_base="http://${U64_IP}/v1"
ftp_url="ftp://${U64_IP}/flash/data/${VPL_NAME}"

die() {
  printf 'ERROR: %s\n' "$*" >&2
  exit 1
}

need() {
  command -v "$1" >/dev/null 2>&1 || die "missing required command: $1"
}

urlencode() {
  local input="${1}"
  local output=""
  local i char hex
  LC_ALL=C
  for ((i = 0; i < ${#input}; i++)); do
    char="${input:i:1}"
    case "$char" in
      [a-zA-Z0-9.~_-]) output+="$char" ;;
      ' ') output+="%20" ;;
      *) printf -v hex '%%%02X' "'$char"; output+="$hex" ;;
    esac
  done
  printf '%s' "$output"
}

rest_call() {
  local method="$1"
  local url="$2"
  local label="$3"
  local body_file
  local code

  body_file="$(mktemp)"
  code="$(curl -sS -X "$method" -o "$body_file" -w '%{http_code}' "$url")" || {
    cat "$body_file" >&2 || true
    rm -f "$body_file"
    die "REST ${label} request failed"
  }

  printf '%s HTTP %s\n' "$label" "$code"
  if [[ -s "$body_file" ]]; then
    cat "$body_file"
    printf '\n'
  fi

  if [[ "$code" -lt 200 || "$code" -ge 300 ]]; then
    rm -f "$body_file"
    die "REST ${label} returned HTTP ${code}"
  fi

  rm -f "$body_file"
}

need curl
[[ -f "$VPL_FILE" ]] || die "VPL file not found: $VPL_FILE"

if [[ "$SKIP_UPLOAD" == "1" ]]; then
  printf 'Skipping FTP upload; expecting /flash/data/%s to exist already\n' "$VPL_NAME"
else
  printf 'Uploading %s to ftp://%s/flash/data/%s\n' "$VPL_FILE" "$U64_IP" "$VPL_NAME"
  curl --fail --silent --show-error --ftp-create-dirs -T "$VPL_FILE" "$ftp_url" \
    --user "${FTP_USER}:${FTP_PASS}" \
    || die "FTP upload failed"
fi

printf 'Verifying uploaded file via REST\n'
rest_call GET "${api_base}/files/flash/data/${VPL_NAME}:info" "file info"

category="$(urlencode 'U64 Specific Settings')"
item="$(urlencode 'Palette Definition')"
value="$(urlencode "$VPL_NAME")"

printf 'Applying palette via REST config\n'
rest_call PUT "${api_base}/configs/${category}/${item}?value=${value}" "apply palette"

printf 'Reading palette config back\n'
rest_call GET "${api_base}/configs/${category}/${item}" "read palette config"

if [[ "$SAVE_TO_FLASH" == "1" ]]; then
  printf 'Saving config to flash\n'
  rest_call PUT "${api_base}/configs:save_to_flash" "save config"
else
  printf 'Not saving config to flash. Run with SAVE_TO_FLASH=1 to persist the config.\n'
fi

printf 'Done.\n'
