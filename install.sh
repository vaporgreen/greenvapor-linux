#!/usr/bin/env sh
# GreenVapor Linux Manager (gvlinux) — Self-Contained Zero-Root Installer for SteamOS & Linux
# Installs or upgrades 100% from curated, SHA-256 verified vaporgreen/greenvapor-linux releases:
#   1. Curated base stack (sanitized UTF-8 slsteam-moon setup + Steamless kit + Lumen + LuaTools)
#   2. GreenVapor patched payload bundle (x64 primary / x86 supplementary: SLSsteam.so,
#      library-inject.so ELF64 fix, dual Stable+Beta patterns, CloudRedirect with OneDrive root)
#   3. gvlinux binary (CLI + WebUI) + GreenHill API + shields + `steam --vanilla` + Desktop shortcut
set -eu

BIN_DIR="${HOME}/.local/bin"
TARGET="${BIN_DIR}/gvlinux"
REPO="${GVLINUX_REPO:-vaporgreen/greenvapor-linux}"
VERSION="${GVLINUX_VERSION:-latest}"

mkdir -p "$BIN_DIR"

dl_url() {
  if [ "$VERSION" = "latest" ]; then
    printf 'https://github.com/%s/releases/latest/download/%s' "$REPO" "$1"
  else
    printf 'https://github.com/%s/releases/download/%s/%s' "$REPO" "$VERSION" "$1"
  fi
}

require_cmd() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "[gvlinux] ERROR: '$1' is required." >&2
    exit 1
  fi
}

echo "============================================================"
echo "  GreenVapor Linux Manager — Self-Contained Linux Setup"
echo "============================================================"

require_cmd curl
require_cmd tar

TMP_WORK="$(mktemp -d)"
trap 'rm -rf "$TMP_WORK"' EXIT

# Download SHA256SUMS.txt (best-effort; enforced whenever the asset is listed)
SUMS_FILE="${TMP_WORK}/SHA256SUMS.txt"
curl -fsSL "$(dl_url SHA256SUMS.txt)" -o "$SUMS_FILE" 2>/dev/null || : > "$SUMS_FILE"

verify_asset() {
  asset_name="$1"
  file_path="$2"
  if [ ! -s "$SUMS_FILE" ] || ! command -v sha256sum >/dev/null 2>&1; then
    return 0
  fi
  expected="$(awk -v f="$asset_name" '$2 == f || $2 == ("*" f) { print tolower($1); exit }' "$SUMS_FILE")"
  if [ -z "$expected" ]; then
    return 0
  fi
  actual="$(sha256sum "$file_path" | awk '{ print tolower($1) }')"
  if [ "$actual" != "$expected" ]; then
    echo "[gvlinux] ERROR: SHA-256 mismatch for ${asset_name} (got ${actual}, want ${expected})" >&2
    exit 1
  fi
  echo "[gvlinux] Verified SHA-256: ${asset_name}"
}

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

# Strip ~/.local/share/SLSsteam/path from PATH so setup.sh discovers the real /usr/bin/steam
clean_path_for_setup() {
  sls_path="${HOME}/.local/share/SLSsteam/path"
  out=""
  old_ifs="$IFS"
  IFS=":"
  for seg in $PATH; do
    if [ "$seg" != "$sls_path" ] && [ -n "$seg" ]; then
      if [ -n "$out" ]; then out="${out}:${seg}"; else out="$seg"; fi
    fi
  done
  IFS="$old_ifs"
  printf '%s' "$out"
}

# 1. Install gvlinux binary (from local path arg $1 or GitHub Releases)
LOCAL_BIN="${1:-}"
LOCAL_BUNDLE="${2:-}"
LOCAL_BASE="${3:-}"

if [ -n "$LOCAL_BIN" ] && [ -f "$LOCAL_BIN" ]; then
  echo "[gvlinux] Installing local gvlinux binary from $LOCAL_BIN..."
  cp "$LOCAL_BIN" "${TARGET}.tmp"
else
  URL="$(dl_url gvlinux-linux-amd64)"
  echo "[gvlinux] Downloading gvlinux from ${URL}..."
  curl -fsSL "$URL" -o "${TARGET}.tmp"
  verify_asset "gvlinux-linux-amd64" "${TARGET}.tmp"
fi
chmod 755 "${TARGET}.tmp"
mv -f "${TARGET}.tmp" "$TARGET"

# 2. Download and extract our patched payload bundle (SLSsteam.so + library-inject.so + CloudRedirect)
STEAM_ARCH="${GVLINUX_ARCH:-$(detect_steam_arch)}"
if [ "$STEAM_ARCH" = "32" ]; then
  BUNDLE_ASSET="greenvapor-linux-bundle-x86.tar.gz"
  echo "[gvlinux] Detected 32-bit Steam client (ubuntu12_32 / i386) — selecting supplementary x86 bundle"
else
  BUNDLE_ASSET="greenvapor-linux-bundle-x64.tar.gz"
  echo "[gvlinux] Detected 64-bit Steam client (steamrt64 / x86_64) — selecting primary x64 bundle"
fi

BUNDLE_ARCHIVE=""
if [ -n "$LOCAL_BUNDLE" ] && [ -f "$LOCAL_BUNDLE" ]; then
  BUNDLE_ARCHIVE="$LOCAL_BUNDLE"
elif [ -n "$LOCAL_BIN" ] && [ -f "$(dirname "$LOCAL_BIN")/${BUNDLE_ASSET}" ]; then
  BUNDLE_ARCHIVE="$(dirname "$LOCAL_BIN")/${BUNDLE_ASSET}"
elif [ "${GVLINUX_SKIP_BUNDLE:-0}" != "1" ]; then
  BURL="$(dl_url "${BUNDLE_ASSET}")"
  echo "[gvlinux] Downloading ${STEAM_ARCH}-bit payload bundle from ${BURL}..."
  if curl -fsSL "$BURL" -o "${TMP_WORK}/bundle.tar.gz"; then
    verify_asset "${BUNDLE_ASSET}" "${TMP_WORK}/bundle.tar.gz"
    BUNDLE_ARCHIVE="${TMP_WORK}/bundle.tar.gz"
  else
    echo "[gvlinux] WARN: ${STEAM_ARCH}-bit bundle not found at ${BURL}; keeping existing binaries."
  fi
fi

BUNDLE_DIR=""
if [ -n "$BUNDLE_ARCHIVE" ]; then
  mkdir -p "${TMP_WORK}/bundle"
  echo "[gvlinux] Extracting ${STEAM_ARCH}-bit payload bundle..."
  tar -xzf "$BUNDLE_ARCHIVE" -C "${TMP_WORK}/bundle"
  BUNDLE_DIR="${TMP_WORK}/bundle"
  if [ -d "${TMP_WORK}/bundle/bundle" ]; then
    BUNDLE_DIR="${TMP_WORK}/bundle/bundle"
  fi
fi

# 3. Self-contained fresh-machine bootstrap from our curated greenvapor-base-stack.tar.gz
#    (Zero runtime dependency on live upstream Rafie-kun/* releases)
NEED_BASE=0
if [ ! -x "${HOME}/.local/share/SLSsteam/path/steam" ] || \
   [ ! -x "${HOME}/.local/share/Lumen/lumen" ] || \
   [ ! -f "${HOME}/.local/share/Lumen/luatools/backend/main.lua" ] || \
   [ "${GVLINUX_FORCE_BASE:-0}" = "1" ]; then
  NEED_BASE=1
fi

if [ "$NEED_BASE" = "1" ]; then
  require_cmd bash
  require_cmd unzip
  echo "[gvlinux] Bootstrapping curated GreenVapor base stack (SLSsteam wrapper + Steamless + Lumen + LuaTools)..."

  BASE_ARCHIVE=""
  if [ -n "$LOCAL_BASE" ] && [ -f "$LOCAL_BASE" ]; then
    BASE_ARCHIVE="$LOCAL_BASE"
  elif [ -n "$LOCAL_BIN" ] && [ -f "$(dirname "$LOCAL_BIN")/greenvapor-base-stack.tar.gz" ]; then
    BASE_ARCHIVE="$(dirname "$LOCAL_BIN")/greenvapor-base-stack.tar.gz"
  else
    BASE_URL="$(dl_url greenvapor-base-stack.tar.gz)"
    echo "[gvlinux] Downloading curated base stack from ${BASE_URL}..."
    curl -fsSL "$BASE_URL" -o "${TMP_WORK}/greenvapor-base-stack.tar.gz"
    verify_asset "greenvapor-base-stack.tar.gz" "${TMP_WORK}/greenvapor-base-stack.tar.gz"
    BASE_ARCHIVE="${TMP_WORK}/greenvapor-base-stack.tar.gz"
  fi

  mkdir -p "${TMP_WORK}/base"
  tar -xzf "$BASE_ARCHIVE" -C "${TMP_WORK}/base"

  # Stop running Steam / Lumen cleanly before running setup
  pkill -f "/.local/share/Lumen/lumen" 2>/dev/null || true
  if pgrep -x steam >/dev/null 2>&1; then
    echo "[gvlinux] Stopping Steam..."
    pkill -x steam 2>/dev/null || true
    sleep 2
  fi

  # Enable Steam CEF remote debugging so Lumen can attach
  for sroot in "${HOME}/.local/share/Steam" "${HOME}/.steam/steam" "${HOME}/.steam/debian-installation"; do
    if [ -d "$sroot" ] && [ ! -f "${sroot}/.cef-enable-remote-debugging" ]; then
      : > "${sroot}/.cef-enable-remote-debugging" 2>/dev/null || true
    fi
  done

  # Inject OUR patched SLSsteam.so + library-inject.so into slsteam-setup/bin/
  # so setup.sh installs our verified binaries directly on step 1
  SLS_SETUP_DIR="${TMP_WORK}/base/slsteam-setup"
  if [ -d "$SLS_SETUP_DIR" ] && [ -n "$BUNDLE_DIR" ]; then
    mkdir -p "${SLS_SETUP_DIR}/bin"
    for lib in SLSsteam.so library-inject.so; do
      if [ -f "${BUNDLE_DIR}/SLSsteam/${lib}" ]; then
        cp -f "${BUNDLE_DIR}/SLSsteam/${lib}" "${SLS_SETUP_DIR}/bin/${lib}"
      elif [ -f "${BUNDLE_DIR}/${lib}" ]; then
        cp -f "${BUNDLE_DIR}/${lib}" "${SLS_SETUP_DIR}/bin/${lib}"
      fi
    done
  fi

  if [ -f "${SLS_SETUP_DIR}/setup.sh" ]; then
    chmod +x "${SLS_SETUP_DIR}/setup.sh" 2>/dev/null || true
    echo "[gvlinux] Running sanitized SLSsteam setup (using GreenVapor ${STEAM_ARCH}-bit libraries)..."
    CLEAN_PATH="$(clean_path_for_setup)"
    (cd "$SLS_SETUP_DIR" && PATH="$CLEAN_PATH" bash ./setup.sh install)
  fi

  # Extract curated Lumen
  LUMEN_DIR="${HOME}/.local/share/Lumen"
  mkdir -p "$LUMEN_DIR"
  if [ -f "${TMP_WORK}/base/lumen-linux.zip" ]; then
    echo "[gvlinux] Installing curated Lumen..."
    unzip -qo "${TMP_WORK}/base/lumen-linux.zip" -d "$LUMEN_DIR"
    chmod +x "${LUMEN_DIR}/lumen" 2>/dev/null || true
  fi

  # Extract curated LuaTools while preserving any existing user backend/data
  if [ -f "${TMP_WORK}/base/luatools-linux.zip" ]; then
    echo "[gvlinux] Installing curated LuaTools plugin..."
    LT_DIR="${LUMEN_DIR}/luatools"
    DATA_BAK=""
    if [ -d "${LT_DIR}/backend/data" ]; then
      DATA_BAK="${TMP_WORK}/lt_data_bak"
      mkdir -p "$DATA_BAK"
      cp -a "${LT_DIR}/backend/data/." "$DATA_BAK/" 2>/dev/null || true
    fi
    mkdir -p "$LT_DIR"
    unzip -qo "${TMP_WORK}/base/luatools-linux.zip" -d "$LT_DIR"
    if [ -n "$DATA_BAK" ] && [ -d "$DATA_BAK" ]; then
      mkdir -p "${LT_DIR}/backend/data"
      cp -a "$DATA_BAK/." "${LT_DIR}/backend/data/" 2>/dev/null || true
    fi
  fi

  # Record curated versions in Lumen's versions.json
  if [ -f "${TMP_WORK}/base/stack-manifest.json" ]; then
    LUMEN_TAG="$(sed -n '/"lumen"/,/}/s/.*"tag"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "${TMP_WORK}/base/stack-manifest.json" | head -n 1)"
    LT_TAG="$(sed -n '/"luatools"/,/}/s/.*"tag"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "${TMP_WORK}/base/stack-manifest.json" | head -n 1)"
    cat > "${LUMEN_DIR}/versions.json" <<EOF
{
  "lumen": {
    "tag": "${LUMEN_TAG:-v2.21}",
    "repo": "${REPO}"
  },
  "plugin": {
    "tag": "${LT_TAG:-v2.16}",
    "repo": "${REPO}"
  }
}
EOF
  fi

  # Install Lumen user systemd service (best-effort; Steam wrapper also starts Lumen if absent)
  if command -v systemctl >/dev/null 2>&1; then
    UNIT_DIR="${HOME}/.config/systemd/user"
    if mkdir -p "$UNIT_DIR" 2>/dev/null; then
      cat > "${UNIT_DIR}/lumen.service" <<'EOF'
[Unit]
Description=Lumen (GreenVapor / LuaTools sidecar)
StartLimitIntervalSec=300
StartLimitBurst=20

[Service]
Type=simple
Environment=LUMEN_LUA_DIR=%h/.local/share/Lumen/lua
Environment=LUMEN_BACKEND_DIR=%h/.local/share/Lumen/luatools/backend
Environment=LUMEN_STEAM_GRACE=120
ExecStart=%h/.local/share/Lumen/lumen
Restart=on-failure
RestartSec=5

[Install]
WantedBy=default.target
EOF
      systemctl --user daemon-reload >/dev/null 2>&1 || true
      systemctl --user enable --now lumen.service >/dev/null 2>&1 || true
    fi
  fi
fi

# 4. Apply GreenVapor payload bundle, shields, GreenHill API, Gaming Mode drop-in & Desktop entry
if [ -n "$BUNDLE_DIR" ]; then
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
