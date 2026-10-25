#!/usr/bin/env bash
# Rescan D:\ota-site for every *.ipa and refresh the Safari install page.
set -euo pipefail
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OTA_SITE_DIR="${OTA_SITE_DIR:-/mnt/d/ota-site}"
OTA_BASE_URL="${OTA_BASE_URL:-https://w77.tail708c1b.ts.net}"
python3 "$script_dir/gen-ota-manifest.py" \
  --scan-all \
  --base-url "$OTA_BASE_URL" \
  --out-dir "$OTA_SITE_DIR"
echo "Refresh ${OTA_BASE_URL%/}/"
