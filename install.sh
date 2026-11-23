#!/usr/bin/env sh
# GreenVapor Linux Manager (gvlinux) — Complete Zero-Root Installer for SteamOS & Linux x86_64
# Installs or upgrades:
#   1. Base stack (Lumen + LuaTools + SLSsteam wrapper + Steamless kit) if not present
#   2. GreenVapor 64-bit patched bundle (SLSsteam.so, library-inject.so ELF64 fix,
#      pattern-refresh, full 64-bit cloud_redirect.so + cloud_redirect_cli with custom OneDrive folder)
#   3. gvlinux binary (CLI + visual WebUI) + KDE/Desktop shortcut + `steam --vanilla`
set -eu

BIN_DIR="${HOME}/.local/bin"
TARGET="${BIN_DIR}/gvlinux"
REPO="${GVLINUX_REPO:-vaporgreen/greenvapor-linux}"
VERSION="${GVLINUX_VERSION:-latest}"
BASE_INSTALLER_URL="${GVLINUX_BASE_INSTALLER:-https://raw.githubusercontent.com/Rafie-kun/luatools-moon/main/install.sh}"

mkdir -p "$BIN_DIR"

dl_url() {
  if [ "$VERSION" = "latest" ]; then
    printf 'https://github.com/%s/releases/latest/download/%s' "$REPO" "$1"
  else
    printf 'https://github.com/%s/releases/download/%s/%s' "$REPO" "$VERSION" "$1"
  fi
}

echo "============================================================"
echo "  GreenVapor Linux Manager — 64-bit SteamOS / Linux Setup"
echo "============================================================"

# 1. Bootstrap base Lumen + LuaTools + Steamless kit on fresh machines
if [ ! -x "${HOME}/.local/share/SLSsteam/path/steam" ] || [ ! -x "${HOME}/.local/share/Lumen/lumen" ]; then
  echo "[gvlinux] Fresh machine detected — installing base Lumen / LuaTools / Steamless stack..."
  if ! command -v curl >/dev/null 2>&1; then
    echo "[gvlinux] ERROR: curl is required." >&2
    exit 1
  fi
  if ! command -v bash >/dev/null 2>&1; then
    echo "[gvlinux] ERROR: bash is required to run the base installer." >&2
    exit 1
  fi
  curl -fsSL "$BASE_INSTALLER_URL" | bash -s -- --unattended --nolaunch || \
    echo "[gvlinux] WARN: base installer returned non-zero; continuing with GreenVapor 64-bit bundle..."
fi

# 2. Install gvlinux binary (from local path arg $1 or GitHub Releases)
LOCAL_BIN="${1:-}"
LOCAL_BUNDLE="${2:-}"

if [ -n "$LOCAL_BIN" ] && [ -f "$LOCAL_BIN" ]; then
  echo "[gvlinux] Installing local gvlinux binary from $LOCAL_BIN..."
  cp "$LOCAL_BIN" "${TARGET}.tmp"
else
  URL="$(dl_url gvlinux-linux-amd64)"
  echo "[gvlinux] Downloading gvlinux from ${URL}..."
  curl -fsSL "$URL" -o "${TARGET}.tmp"
fi
chmod 755 "${TARGET}.tmp"
mv -f "${TARGET}.tmp" "$TARGET"

# Detect Steam client architecture (64-bit steamrt64 default, 32-bit ubuntu12_32 supplementary)
detect_steam_arch() {
  for root in "${HOME}/.local/share/Steam" "${HOME}/.steam/steam" "${HOME}/.steam/debian-installation"; do
    if [ -d "$root" ]; then
      if [ -f "${root}/steamrt64/steam" ] && [ ! -f "${root}/.steam-disable-steamrt64-client" ] && [ "${STEAM_FORCE_CLIENT:-}" != "ubuntu12_32" ]; then
        if [ ! -f "${root}/steamrt3/steam" ]; then
          echo 64
          return
        fi
      fi
      if [ -f "${root}/ubuntu12_32/steam" ] || [ -f "${root}/steamrt32/steam" ] || [ -f "${root}/steamrt3/steam" ]; then
        echo 32
        return
      fi
    fi
  done
  echo 64
}

STEAM_ARCH="${GVLINUX_ARCH:-$(detect_steam_arch)}"
if [ "$STEAM_ARCH" = "32" ]; then
  BUNDLE_ASSET="greenvapor-linux-bundle-x86.tar.gz"
  echo "[gvlinux] Detected 32-bit Steam client (ubuntu12_32 / i386) — selecting supplementary x86 bundle"
else
  BUNDLE_ASSET="greenvapor-linux-bundle-x64.tar.gz"
  echo "[gvlinux] Detected 64-bit Steam client (steamrt64 / x86_64) — selecting primary x64 bundle"
fi

# 3. Extract and install our patched payload bundle (SLSsteam.so + library-inject.so + CloudRedirect)
TMP_BUNDLE="$(mktemp -d)"
trap 'rm -rf "$TMP_BUNDLE"' EXIT

BUNDLE_ARCHIVE=""
if [ -n "$LOCAL_BUNDLE" ] && [ -f "$LOCAL_BUNDLE" ]; then
  BUNDLE_ARCHIVE="$LOCAL_BUNDLE"
elif [ -n "$LOCAL_BIN" ] && [ -f "$(dirname "$LOCAL_BIN")/${BUNDLE_ASSET}" ]; then
  BUNDLE_ARCHIVE="$(dirname "$LOCAL_BIN")/${BUNDLE_ASSET}"
elif [ "${GVLINUX_SKIP_BUNDLE:-0}" != "1" ]; then
  BURL="$(dl_url "${BUNDLE_ASSET}")"
  echo "[gvlinux] Downloading ${STEAM_ARCH}-bit payload bundle from ${BURL}..."
  if curl -fsSL "$BURL" -o "${TMP_BUNDLE}/bundle.tar.gz"; then
    BUNDLE_ARCHIVE="${TMP_BUNDLE}/bundle.tar.gz"
  else
    echo "[gvlinux] WARN: ${STEAM_ARCH}-bit bundle not found at ${BURL}; keeping existing binaries."
  fi
fi

if [ -n "$BUNDLE_ARCHIVE" ]; then
  echo "[gvlinux] Extracting 64-bit payload bundle..."
  tar -xzf "$BUNDLE_ARCHIVE" -C "$TMP_BUNDLE"
  BUNDLE_DIR="$TMP_BUNDLE"
  if [ -d "${TMP_BUNDLE}/bundle" ]; then
    BUNDLE_DIR="${TMP_BUNDLE}/bundle"
  fi
  "$TARGET" install --bundle "$BUNDLE_DIR"
else
  "$TARGET" install
fi

# Ensure ~/.local/bin is in PATH for interactive shells
case ":${PATH}:" in
  *":${BIN_DIR}:"*) ;;
  *)
    for rc in "${HOME}/.bashrc" "${HOME}/.zshrc"; do
      if [ -f "$rc" ] && ! grep -q '\.local/bin' "$rc" 2>/dev/null; then
        printf '\nexport PATH="$HOME/.local/bin:$PATH"\n' >> "$rc"
      fi
    done
    ;;
esac

echo ""
echo "[gvlinux] Running diagnostics (gvlinux doctor)..."
"$TARGET" doctor || true

echo ""
echo "============================================================"
echo "  GreenVapor Linux Manager installed!"
echo "  Visual UI : ${TARGET} gui  (or open 'GreenVapor Linux Manager' in App Menu)"
echo "  Doctor    : ${TARGET} doctor"
echo "  Games/DRM : ${TARGET} games"
echo "  Cloud     : ${TARGET} cloud"
echo "  Vanilla   : steam --vanilla"
echo "============================================================"
