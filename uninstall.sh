#!/bin/bash
# Removes Uyku and puts the Mac back to normal sleep.
set -uo pipefail

APP="$HOME/Applications/Uyku.app"

if [ -x "$APP/Contents/MacOS/Uyku" ]; then
  "$APP/Contents/MacOS/Uyku" --login-off 2>/dev/null || true
fi
pkill -x Uyku 2>/dev/null || true
rm -rf "$APP"
defaults delete local.uyku.anahtar 2>/dev/null || true

if pmset -g | grep -q "SleepDisabled.*1"; then
  echo "Sleep is still disabled. Turning it back on (asks for your password)..."
  sudo pmset -a disablesleep 0
fi
if [ -e /etc/sudoers.d/uyku ]; then
  echo "Removing the passwordless rule (asks for your password)..."
  sudo rm -f /etc/sudoers.d/uyku
fi

echo "Uyku is removed."
