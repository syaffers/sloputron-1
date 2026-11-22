#!/usr/bin/env bash
# One-shot setup of a Debian (trixie) machine for sloputron-1 development with an iCEstick.
# Idempotent: safe to re-run. Needs sudo for apt, udev rules and group membership.
#
#   scripts/setup_debian.sh            # packages + udev + groups + pinned OSS CAD Suite
#   scripts/setup_debian.sh --no-tools # skip the toolchain download (~700 MB)
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)

echo "== apt packages"
sudo apt-get update
sudo apt-get install -y git make curl ca-certificates python3 python3-serial picocom

echo "== udev rule for the iCEstick's FT2232H (0403:6010)"
# Gives the logged-in user access to the FTDI device so iceprog runs without sudo.
# Channel B keeps the ftdi_sio driver (-> /dev/ttyUSB1); iceprog detaches channel A itself.
sudo tee /etc/udev/rules.d/53-lattice-ftdi.rules > /dev/null <<'EOF'
ACTION=="add|change", SUBSYSTEM=="usb", ATTRS{idVendor}=="0403", ATTRS{idProduct}=="6010", MODE="0660", GROUP="plugdev", TAG+="uaccess"
EOF
sudo udevadm control --reload-rules
sudo udevadm trigger

echo "== groups (dialout for /dev/ttyUSB*, plugdev for USB)"
sudo usermod -aG dialout,plugdev "$USER"

if [ "${1:-}" != "--no-tools" ]; then
  echo "== pinned OSS CAD Suite"
  case $(uname -m) in
    x86_64)  plat=linux-x64 ;;
    aarch64) plat=linux-arm64 ;;
    *) echo "unsupported arch $(uname -m)"; exit 1 ;;
  esac
  if [ -x "$ROOT/tools/oss-cad-suite/bin/yosys" ]; then
    echo "already present: $ROOT/tools/oss-cad-suite"
  else
    "$ROOT/scripts/fetch_toolchain.sh" "$plat"
  fi
fi

cat <<EOF

Done. Log out and back in (or reboot) so the new group membership applies.
The Makefile finds tools/oss-cad-suite automatically. Then, with the iCEstick plugged in:

  make bits                    # build/blinky.bin, build/uart_echo.bin
  make prog D=blinky           # LEDs should count
  make prog D=uart_echo
  make uart-test               # expects PASS
EOF
