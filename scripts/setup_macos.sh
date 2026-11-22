#!/usr/bin/env bash
# One-shot setup of a Mac (Apple Silicon or Intel) for sloputron-1 development with an iCEstick.
# Idempotent: safe to re-run.
#
#   scripts/setup_macos.sh            # Xcode CLT check, pyserial, pinned OSS CAD Suite
#   scripts/setup_macos.sh --no-tools # skip the toolchain download
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)

echo "== Xcode Command Line Tools (clang for Verilator, git, make)"
if ! xcode-select -p > /dev/null 2>&1; then
  xcode-select --install || true
  echo "Finish the Command Line Tools installer, then re-run this script."
  exit 1
fi

echo "== pyserial (for make uart-test)"
python3 -c "import serial" 2>/dev/null || python3 -m pip install --user pyserial

if command -v brew > /dev/null; then
  echo "== optional Homebrew tools: picocom (serial terminal), coreutils (gtimeout)"
  brew install picocom coreutils || true
else
  echo "== Homebrew not found: skipping picocom/coreutils (optional). 'screen /dev/cu.usbserial-* 115200' works too."
fi

if [ "${1:-}" != "--no-tools" ]; then
  echo "== pinned OSS CAD Suite"
  case $(uname -m) in
    arm64)  plat=darwin-arm64 ;;
    x86_64) plat=darwin-x64 ;;
    *) echo "unsupported arch $(uname -m)"; exit 1 ;;
  esac
  if [ -x "$ROOT/tools/oss-cad-suite/bin/yosys" ]; then
    echo "already present: $ROOT/tools/oss-cad-suite"
  else
    # curl does not set the quarantine attribute, so Gatekeeper does not block the binaries.
    "$ROOT/scripts/fetch_toolchain.sh" "$plat"
  fi
fi

cat <<EOF

Done. The Makefile finds tools/oss-cad-suite automatically. With the iCEstick plugged in:

  make bits
  make prog D=blinky            # LEDs should count
  make prog D=uart_echo
  make uart-test                # expects PASS; picks the last /dev/cu.usbserial-*, or pass PORT=

If iceprog says it can't claim the FTDI device, macOS's FTDI driver holds it:
run 'sudo make prog D=...' (as root, libusb can detach the driver), and unload any
third-party FTDI VCP driver you installed in the past.
EOF
