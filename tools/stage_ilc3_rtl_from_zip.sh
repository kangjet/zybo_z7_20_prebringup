#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ZIP_DEFAULT="$ROOT_DIR/../../ILC3_IPCore_v0.1_usb_review_fixed_2026-03-04.zip"
ZIP_PATH="${1:-$ZIP_DEFAULT}"
OUT_DIR="$ROOT_DIR/rtl/ilc3_core"

if [[ ! -f "$ZIP_PATH" ]]; then
  echo "[ERR] zip not found: $ZIP_PATH" >&2
  exit 1
fi

mkdir -p "$OUT_DIR"

unzip -o -j "$ZIP_PATH" \
  "ILC3_IPCore_v0.1_usb/rtl/core/ilc3_tx_core.v" \
  "ILC3_IPCore_v0.1_usb/rtl/core/ilc3_rx_core.v" \
  "ILC3_IPCore_v0.1_usb/rtl/core/ilc3_ipcore_top.v" \
  -d "$OUT_DIR" >/dev/null

echo "[OK] staged RTL into: $OUT_DIR"
ls -1 "$OUT_DIR"
