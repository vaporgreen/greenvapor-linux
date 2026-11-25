#!/usr/bin/env sh
# GreenVapor Linux Manager (gvlinux) — Clean Zero-Root Uninstaller
# Reverts changes made by install.sh / gvlinux without touching installed games,
# game saves, CloudRedirect config, or ~/.local/share/Steam/config/stplug-in/*.lua.
#
# Usage:
#   curl -fsSL https://raw.githubusercontent.com/vaporgreen/greenvapor-linux/main/uninstall.sh | sh
#   sh uninstall.sh --full    # also removes ~/.local/share/GreenVapor snapshots/cache
set -eu

FULL_CLEAN=0
for arg in "$@"; do
  case "$arg" in
    --full) FULL_CLEAN=1 ;;
    -h|--help)
      echo "Usage: sh uninstall.sh [--full]"
      echo "  Default : removes gvlinux, SLSsteam, Lumen, CloudRedirect hooks, systemd units, and launchers."
      echo "            Preserves games, saves, stplug-in/*.lua, ~/.config/CloudRedirect, and snapshots."
      echo "  --full  : also removes ~/.local/share/GreenVapor (snapshots/cache) and ~/.config/SLSsteam."
      exit 0
      ;;
  esac
done

echo "============================================================"
echo "  GreenVapor Linux Manager — Clean Uninstaller"
echo "============================================================"

# 1. Save a final safety snapshot if gvlinux is still present (unless --full)
if [ "$FULL_CLEAN" = "0" ] && [ -x "${HOME}/.local/bin/gvlinux" ]; then
  echo "[gvlinux] Saving pre-uninstall safety snapshot..."
  "${HOME}/.local/bin/gvlinux" snapshot pre-uninstall >/dev/null 2>&1 || true
fi

# 2. Stop Lumen sidecar and disable/remove systemd user units & Gaming Mode drop-in
if command -v systemctl >/dev/null 2>&1; then
  systemctl --user disable --now lumen.service >/dev/null 2>&1 || true
fi
pkill -f "/.local/share/Lumen/lumen" 2>/dev/null || true

remove_path() {
  target="$1"
  if [ -e "$target" ] || [ -L "$target" ]; then
    rm -rf "$target"
    echo "[gvlinux] Removed: $target"
  fi
}

remove_path "${HOME}/.config/systemd/user/lumen.service"
remove_path "${HOME}/.config/systemd/user/steam-launcher.service.d/greenvapor-gamemode.conf"
rmdir "${HOME}/.config/systemd/user/steam-launcher.service.d" 2>/dev/null || true

if command -v systemctl >/dev/null 2>&1; then
  systemctl --user daemon-reload >/dev/null 2>&1 || true
fi

# 3. Remove GreenVapor / SLSsteam / Lumen / CloudRedirect binaries and wrappers
remove_path "${HOME}/.local/share/SLSsteam"
remove_path "${HOME}/.local/share/CloudRedirect"
remove_path "${HOME}/.local/share/Lumen"
remove_path "${HOME}/.local/bin/gvlinux"
remove_path "${HOME}/.local/share/applications/greenvapor-linux.desktop"

# Only remove user-overridden steam.desktop if it points to SLSsteam / GreenVapor
USER_STEAM_DESKTOP="${HOME}/.local/share/applications/steam.desktop"
if [ -f "$USER_STEAM_DESKTOP" ] && grep -qiE "SLSsteam|GreenVapor" "$USER_STEAM_DESKTOP" 2>/dev/null; then
  remove_path "$USER_STEAM_DESKTOP"
fi

# Refresh desktop database so Steam / KDE menus immediately revert to stock /usr/bin/steam
if command -v update-desktop-database >/dev/null 2>&1; then
  update-desktop-database "${HOME}/.local/share/applications" >/dev/null 2>&1 || true
fi

# Remove Decky GreenVapor plugin if user-writable
DECKY_GV="${HOME}/homebrew/plugins/GreenVapor"
if [ -d "$DECKY_GV" ]; then
  if [ -w "$DECKY_GV" ] && [ -w "$(dirname "$DECKY_GV")" ]; then
    remove_path "$DECKY_GV"
  else
    echo "[gvlinux] Note: Decky plugin at ${DECKY_GV} is root-owned; remove it via Decky Loader -> Plugins -> Uninstall."
  fi
fi

# Optional --full cleanup of GreenVapor cache/snapshots and SLSsteam config
if [ "$FULL_CLEAN" = "1" ]; then
  remove_path "${HOME}/.local/share/GreenVapor"
  remove_path "${HOME}/.config/SLSsteam"
fi

echo ""
echo "============================================================"
echo "  GreenVapor Linux uninstalled cleanly!"
echo "  Preserved (untouched):"
echo "    - Installed Steam games & Proton prefixes (compatdata)"
echo "    - Game saves & ~/.config/CloudRedirect"
echo "    - Lua scripts (~/.local/share/Steam/config/stplug-in/)"
if [ "$FULL_CLEAN" = "0" ]; then
  echo "    - Rollback snapshots (~/.local/share/GreenVapor/)"
fi
echo "  Restart Steam to return to stock vanilla Steam."
echo "============================================================"
