#!/usr/bin/env bash
# QBerry🫐 (qberry-cli) — Linux / macOS curl+bash installer ✨
#
# Usage:
#   curl -fsSL https://raw.githubusercontent.com/yui0/qBerryOS/master/install.sh | sudo bash
#   curl -fsSL https://raw.githubusercontent.com/yui0/qBerryOS/master/install.sh | sudo bash -s -- --gateway
#   curl -fsSL https://raw.githubusercontent.com/yui0/qBerryOS/master/install.sh | sudo bash -s -- --broadcast
#   curl -fsSL https://raw.githubusercontent.com/yui0/qBerryOS/master/install.sh | sudo bash -s -- --profile-name mynet --profile-password secret
#   curl -fsSL https://raw.githubusercontent.com/yui0/qBerryOS/master/install.sh | sudo bash -s -- --version 2026.5.14
#   curl -fsSL https://raw.githubusercontent.com/yui0/qBerryOS/master/install.sh | sudo bash -s -- --uninstall
#
# Options:
#   --version <tag>            Release tag to install (default: latest)
#   --prefix  <dir>            Install prefix (default: /usr/local)
#   --gateway                  Add `--gateway` to systemd/launchd ExecStart
#   --broadcast                Set broadcast=true in qberry.toml
#   --profile-name <name>      Auth profile name written to qberry.toml; enables auth_enabled=true
#   --profile-password <pass>  Auth profile password written to qberry.toml
#   --no-service               Do not configure a systemd/launchd service
#   --no-start                 Do not enable / start the service
#   --uninstall                Remove binary and service (keep config files)
#
# Equivalent environment variables:
#   QFKEY_VERSION, QFKEY_PREFIX, QFKEY_GATEWAY=1, QFKEY_BROADCAST=1,
#   QFKEY_PROFILE_NAME, QFKEY_PROFILE_PASSWORD, QFKEY_NO_SERVICE=1, QFKEY_NO_START=1
set -euo pipefail

REPO="yui0/qBerryOS"
# macOS release binary is named "qberry"; Linux release is "qberry-cli"
case "$(uname -s)" in
  Darwin*) BIN_NAME="qberry" ;;
  *)       BIN_NAME="qberry-cli" ;;
esac
SERVICE_NAME="qberry"
STATE_DIR="/var/lib/${BIN_NAME}"
CONFIG_FILE="/etc/qberry.toml"
ENV_FILE="/etc/qberry.env"

# macOS launchd / app bundle
PLIST_LABEL="net.berry-lab.${SERVICE_NAME}"
PLIST_PATH="/Library/LaunchDaemons/${PLIST_LABEL}.plist"
APP_BUNDLE="/Applications/QBerry.app"
BUNDLE_BIN="${APP_BUNDLE}/Contents/MacOS/${BIN_NAME}"

VERSION="${QFKEY_VERSION:-latest}"
PREFIX="${QFKEY_PREFIX:-/usr/local}"
GATEWAY="${QFKEY_GATEWAY:-0}"
BROADCAST="${QFKEY_BROADCAST:-0}"
PROFILE_NAME="${QFKEY_PROFILE_NAME:-}"
PROFILE_PASSWORD="${QFKEY_PROFILE_PASSWORD:-}"
NO_SERVICE="${QFKEY_NO_SERVICE:-0}"
NO_START="${QFKEY_NO_START:-0}"
DO_UNINSTALL=0
_TMP=""

log()  { printf '\033[1;34m==>\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[!]\033[0m %s\n' "$*" >&2; }
die()  { printf '\033[1;31m[x]\033[0m %s\n' "$*" >&2; exit 1; }

while [ $# -gt 0 ]; do
  case "$1" in
    --version)            VERSION="${2:?--version requires a value}"; shift 2 ;;
    --version=*)          VERSION="${1#*=}"; shift ;;
    --prefix)             PREFIX="${2:?--prefix requires a value}"; shift 2 ;;
    --prefix=*)           PREFIX="${1#*=}"; shift ;;
    --gateway)            GATEWAY=1; shift ;;
    --broadcast)          BROADCAST=1; shift ;;
    --profile-name)       PROFILE_NAME="${2:?--profile-name requires a value}"; shift 2 ;;
    --profile-name=*)     PROFILE_NAME="${1#*=}"; shift ;;
    --profile-password)   PROFILE_PASSWORD="${2:?--profile-password requires a value}"; shift 2 ;;
    --profile-password=*) PROFILE_PASSWORD="${1#*=}"; shift ;;
    --no-service)         NO_SERVICE=1; shift ;;
    --no-start)           NO_START=1; shift ;;
    --uninstall)          DO_UNINSTALL=1; shift ;;
    -h|--help)            sed -n '2,25p' "$0"; exit 0 ;;
    *) die "Unknown argument: $1" ;;
  esac
done

BIN_DIR="${PREFIX}/bin"
BIN_PATH="${BIN_DIR}/${BIN_NAME}"
SERVICE_PATH="/etc/systemd/system/${SERVICE_NAME}.service"

require_root() {
  if [ "$(id -u)" -ne 0 ]; then
    die "Root privileges are required. Pipe to 'sudo bash' or run with sudo. 🙇"
  fi
}

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "Command not found: $1"
}

detect_os() {
  case "$(uname -s)" in
    Linux*)  echo "linux" ;;
    Darwin*) echo "macos" ;;
    *) die "Unsupported OS: $(uname -s) (supported: Linux / macOS only)" ;;
  esac
}

detect_arch() {
  local m
  m="$(uname -m)"
  case "$m" in
    x86_64|amd64)   echo "x86_64" ;;
    aarch64|arm64)  echo "aarch64" ;;
    *) die "Unsupported architecture: $m (supported: x86_64 / aarch64 only)" ;;
  esac
}

# Portable sed -i: macOS requires an explicit backup extension (use empty string for in-place)
sed_i() {
  if [ "$(detect_os)" = "macos" ]; then
    sed -i '' "$@"
  else
    sed -i "$@"
  fi
}

uninstall() {
  require_root
  local os
  os="$(detect_os)"
  log "Uninstalling qberry-cli 🧹"

  if [ "$os" = "macos" ]; then
    if [ -f "$PLIST_PATH" ]; then
      launchctl unload "$PLIST_PATH" 2>/dev/null || true
      rm -f "$PLIST_PATH"
    fi
    rm -rf "$APP_BUNDLE"
  else
    if systemctl list-unit-files 2>/dev/null | grep -q "^${SERVICE_NAME}.service"; then
      systemctl stop    "${SERVICE_NAME}" 2>/dev/null || true
      systemctl disable "${SERVICE_NAME}" 2>/dev/null || true
    fi
    rm -f "${SERVICE_PATH}"
    systemctl daemon-reload 2>/dev/null || true
  fi

  rm -f "${BIN_PATH}"
  rm -f "/usr/bin/${BIN_NAME}" "/usr/local/bin/${BIN_NAME}"
  log "Uninstall complete ✅ (kept ${CONFIG_FILE}, ${ENV_FILE}, and state dir ${STATE_DIR})"
}

resolve_download_url() {
  local os="$1" arch="$2" version="$3"
  local asset
  case "$os" in
    macos) asset="qberry-${os}-${arch}.tar.gz" ;;
    *)     asset="qberry-cli-${os}-${arch}.tar.gz" ;;
  esac
  if [ "$version" = "latest" ]; then
    printf 'https://github.com/%s/releases/latest/download/%s\n' "$REPO" "$asset"
  else
    printf 'https://github.com/%s/releases/download/%s/%s\n' "$REPO" "$version" "$asset"
  fi
}

download() {
  local url="$1" out="$2"
  if command -v curl >/dev/null 2>&1; then
    curl -fL --proto '=https' --tlsv1.2 --retry 3 -o "$out" "$url"
  elif command -v wget >/dev/null 2>&1; then
    wget --https-only -O "$out" "$url"
  else
    die "curl or wget is required"
  fi
}

patch_config() {
  local cfg="$1"
  [ -f "$cfg" ] || return

  if [ "$BROADCAST" = "1" ]; then
    sed_i 's/^broadcast = false$/broadcast = true/' "$cfg"
    log "Config: broadcast = true"
  fi

  if [ -n "$PROFILE_NAME" ] || [ -n "$PROFILE_PASSWORD" ]; then
    sed_i 's/^auth_enabled = false$/auth_enabled = true/' "$cfg"
    local pname="${PROFILE_NAME:-default}"
    local ppass="${PROFILE_PASSWORD:-}"
    cat >> "$cfg" <<EOF

[[auth_profiles]]
name = "${pname}"
password = "${ppass}"
flags = 0
is_default = true
EOF
    log "Config: auth_enabled = true, profile '${pname}' added"
  fi
}

write_service_linux() {
  local exec_args=""
  [ "$GATEWAY" = "1" ] && exec_args=" --gateway"

  log "Writing systemd service file 🛠️: ${SERVICE_PATH}"
  cat > "${SERVICE_PATH}" <<EOF
[Unit]
Description=QBerry🫐 Mesh PQ-VPN (qberry-cli)
After=network-online.target
Wants=network-online.target
Documentation=https://github.com/${REPO}

[Service]
Type=simple
ExecStart=${BIN_PATH}${exec_args}
WorkingDirectory=${STATE_DIR}
User=root
Group=root
Restart=always
RestartSec=5
EnvironmentFile=-${ENV_FILE}
AmbientCapabilities=CAP_NET_ADMIN CAP_NET_RAW
LimitNOFILE=65535

[Install]
WantedBy=multi-user.target
EOF
}

write_info_plist_macos() {
  mkdir -p "${APP_BUNDLE}/Contents/MacOS"
  log "Writing Info.plist 📄: ${APP_BUNDLE}/Contents/Info.plist"
  cat > "${APP_BUNDLE}/Contents/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleIdentifier</key>
    <string>${PLIST_LABEL}</string>
    <key>CFBundleName</key>
    <string>QBerry</string>
    <key>CFBundleDisplayName</key>
    <string>QBerry</string>
    <key>CFBundleExecutable</key>
    <string>${BIN_NAME}</string>
    <key>CFBundleVersion</key>
    <string>1.0</string>
    <key>CFBundleIconFile</key>
    <string>QBerry</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSScreenCaptureUsageDescription</key>
    <string>QBerry needs screen recording access for remote desktop functionality.</string>
    <key>LSMinimumSystemVersion</key>
    <string>12.0</string>
</dict>
</plist>
EOF
}

# Patch Mach-O LC_BUILD_VERSION minos so Finder allows launch on older macOS.
# The release binary is often compiled with minos 13.0; the terminal ignores this
# check but Finder enforces it, producing "requires macOS 13.0 or later".
# Note: this invalidates the code signature — the caller MUST re-sign afterwards.
patch_macos_min_version() {
  local bin="$1" target="${2:-12.0}"
  if ! command -v vtool >/dev/null 2>&1; then
    warn "vtool not found — skipping minos patch (install Xcode Command Line Tools)"
    return
  fi
  local cur
  cur="$(vtool -show-build "$bin" 2>/dev/null | awk '/minos/{print $2; exit}')"
  [ -z "$cur" ] && return
  log "Patching Mach-O minos: ${cur} → ${target} in $(basename "$bin")"
  vtool -set-build-version macos "$target" "$target" -replace -output "$bin" "$bin" 2>/dev/null \
    || warn "vtool patch failed — app bundle may still require macOS 13+"
}

# Sign inner binary then bundle, both with identifier-pinned designated requirement.
# Avoid --deep: it re-signs nested code with the default (cdhash) DR, which
# overwrites the identifier-pinned DR on the inner binary and causes TCC to
# invalidate Screen Recording / Accessibility grants on every reinstall.
sign_bundle_macos() {
  if ! command -v codesign >/dev/null 2>&1; then
    warn "codesign not found — TCC permissions (Screen Recording / Accessibility) will not survive reinstall"
    return
  fi
  local dr="=designated => identifier \"${PLIST_LABEL}\""
  # 1. Sign inner binary first so its DR is identifier-pinned.
  if ! codesign --force --sign - --requirements "$dr" "$BUNDLE_BIN" 2>/dev/null; then
    warn "Inner binary signing failed — falling back to plain ad-hoc"
    codesign --force --sign - "$BUNDLE_BIN" 2>/dev/null || \
      warn "Inner binary ad-hoc sign failed"
  fi
  # 2. Sign bundle (no --deep) so the inner DR set above is preserved.
  if codesign --force --sign - --requirements "$dr" "${APP_BUNDLE}" 2>/dev/null; then
    log "App bundle signed 🔏 (identifier-pinned DR): ${APP_BUNDLE}"
  else
    warn "Identifier-pinned bundle signing failed — falling back to default ad-hoc"
    codesign --force --sign - "${APP_BUNDLE}" 2>/dev/null || \
      warn "Bundle ad-hoc sign failed — Screen Recording permission may not work"
  fi
}

# Reset stale TCC entries pinned to the previous install's cdhash. Without this,
# a leftover row in TCC.db with the old code requirement can mask the new grant
# and produce the "checkbox is on but capture fails" symptom.
reset_tcc_macos() {
  if ! command -v tccutil >/dev/null 2>&1; then
    return
  fi
  log "Resetting stale TCC entries 🧼 (Screen Recording / Accessibility)"
  tccutil reset ScreenCapture "${PLIST_LABEL}" 2>/dev/null || true
  tccutil reset Accessibility "${PLIST_LABEL}" 2>/dev/null || true
}

# Drop Finder/Dock icon caches so the new bundle icon shows up immediately.
refresh_icon_cache_macos() {
  rm -rf /Library/Caches/com.apple.iconservices.store 2>/dev/null || true
  find /private/var/folders -name com.apple.dock.iconcache -delete 2>/dev/null || true
  find /private/var/folders -name com.apple.iconservices -delete 2>/dev/null || true
  killall Dock 2>/dev/null || true
  killall Finder 2>/dev/null || true
}

# Open System Settings > Privacy > Screen Recording and Accessibility so the user can grant access.
open_screen_recording_prefs() {
  local real_user="${SUDO_USER:-}"
  [ -z "$real_user" ] && return
  log "Opening Screen Recording preferences 🖥️ — please enable QBerry and restart the service."
  sudo -u "$real_user" open \
    "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture" \
    2>/dev/null || true
  sleep 1
  log "Opening Accessibility preferences ♿ — please enable QBerry for keyboard/mouse control."
  sudo -u "$real_user" open \
    "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility" \
    2>/dev/null || true
}

write_service_macos() {
  local exec_args=()
  [ "$GATEWAY" = "1" ] && exec_args=("--gateway")

  log "Writing launchd plist 🛠️: ${PLIST_PATH}"
  mkdir -p "$(dirname "$PLIST_PATH")"

  # Build ProgramArguments entries — run from inside the app bundle for TCC/Screen Recording
  local args_xml="        <string>${BUNDLE_BIN}</string>"
  for a in "${exec_args[@]+"${exec_args[@]}"}"; do
    args_xml="${args_xml}
        <string>${a}</string>"
  done

  cat > "${PLIST_PATH}" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>${PLIST_LABEL}</string>
    <key>ProgramArguments</key>
    <array>
${args_xml}
    </array>
    <key>WorkingDirectory</key>
    <string>${STATE_DIR}</string>
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <true/>
    <key>StandardOutPath</key>
    <string>/var/log/${SERVICE_NAME}.log</string>
    <key>StandardErrorPath</key>
    <string>/var/log/${SERVICE_NAME}.error.log</string>
    <key>EnvironmentVariables</key>
    <dict>
        <key>QBERRY_LOG_LEVEL</key>
        <string>off</string>
    </dict>
</dict>
</plist>
EOF
  chmod 0644 "${PLIST_PATH}"
}

setup_service() {
  local os="$1"
  if [ "$NO_SERVICE" = "1" ]; then
    log "Skipping service setup because --no-service was specified 💤"
    return
  fi

  if [ "$os" = "macos" ]; then
    write_service_macos
    open_screen_recording_prefs
    if [ "$NO_START" = "1" ]; then
      log "Skipping launchd load because --no-start was specified 💤"
    else
      launchctl unload "${PLIST_PATH}" 2>/dev/null || true
      launchctl load -w "${PLIST_PATH}"
      sleep 1
      launchctl list | grep "${PLIST_LABEL}" || true
    fi
  else
    if ! command -v systemctl >/dev/null 2>&1; then
      warn "Skipping systemd setup because systemctl was not found"
      return
    fi
    write_service_linux
    systemctl daemon-reload
    if [ "$NO_START" = "1" ]; then
      log "Skipping enable/start because --no-start was specified 💤"
    else
      systemctl enable "${SERVICE_NAME}" >/dev/null
      systemctl restart "${SERVICE_NAME}"
      sleep 1
      systemctl --no-pager --full status "${SERVICE_NAME}" | sed -n '1,8p' || true
    fi
  fi
}

install_main() {
  require_root
  require_cmd tar
  require_cmd uname

  local os arch url tarball
  os="$(detect_os)"
  arch="$(detect_arch)"
  url="$(resolve_download_url "$os" "$arch" "$VERSION")"

  log "Target: ${os}-${arch} / version: ${VERSION}"
  log "Downloading 📦: ${url}"

  _TMP="$(mktemp -d)"
  trap 'rm -rf "$_TMP"' EXIT
  tarball="${_TMP}/${BIN_NAME}.tar.gz"
  download "$url" "$tarball"

  log "Extracting archive... ✨"
  tar -xzf "$tarball" -C "$_TMP"

  local src_bin="${_TMP}/${BIN_NAME}"
  [ -f "$src_bin" ] || src_bin="$(find "$_TMP" -maxdepth 3 -type f -name "${BIN_NAME}" -perm -u+x 2>/dev/null | head -n1)"
  [ -n "${src_bin:-}" ] && [ -f "$src_bin" ] || die "Could not find ${BIN_NAME} in the archive"

  if [ "$os" = "macos" ]; then
    # Stop existing service and remove old bundle before update to avoid stale files
    # and ensure the new code signature is registered cleanly with TCC.
    local is_upgrade=0
    if [ -d "$APP_BUNDLE" ]; then
      is_upgrade=1
      log "Existing install detected — stopping service and removing old bundle 🗑️"
      launchctl unload "${PLIST_PATH}" 2>/dev/null || true
      sleep 1
      rm -rf "$APP_BUNDLE"
    fi

    # Install binary inside the app bundle; symlink from BIN_PATH for CLI convenience
    log "Installing 🚀: ${BUNDLE_BIN}"
    mkdir -p "${APP_BUNDLE}/Contents/MacOS"
    install -m 0755 "$src_bin" "$BUNDLE_BIN"

    # Write Info.plist and install icon BEFORE signing so the bundle is complete
    write_info_plist_macos

    # Install app icon if bundled in the archive
    local src_icns
    src_icns="$(find "$_TMP" -maxdepth 3 -type f -name 'QBerry.icns' 2>/dev/null | head -n1)"
    if [ -n "${src_icns:-}" ]; then
      install -d -m 0755 "${APP_BUNDLE}/Contents/Resources"
      install -m 0644 "$src_icns" "${APP_BUNDLE}/Contents/Resources/QBerry.icns"
      log "Icon installed 🎨: ${APP_BUNDLE}/Contents/Resources/QBerry.icns"
    else
      warn "QBerry.icns not found in archive — app icon will be blank"
    fi

    # Patch minos on the binary, then sign inner-then-outer with identifier-pinned DR.
    # Bundle-level signing is required for TCC (Screen Recording / Accessibility)
    # to recognise the app. Identifier-pinned DR (vs. default cdhash) lets the
    # grant survive binary updates without requiring re-approval — provided we
    # avoid --deep, which would overwrite the inner DR back to cdhash.
    patch_macos_min_version "$BUNDLE_BIN" "12.0"
    sign_bundle_macos

    # Clear stale TCC entries from any previous install (cdhash-pinned grants
    # left over from older install.sh versions will silently block the new bundle).
    reset_tcc_macos
    refresh_icon_cache_macos

    install -d -m 0755 "$BIN_DIR"
    ln -sf "$BUNDLE_BIN" "${BIN_PATH}"
    log "Symlink: ${BIN_PATH} -> ${BUNDLE_BIN}"
  else
    log "Installing 🚀: ${BIN_PATH}"
    install -d -m 0755 "$BIN_DIR"
    install -m 0755 "$src_bin" "$BIN_PATH"
  fi

  install -d -m 0755 "$STATE_DIR"

  # Default config file: keep existing file if already present
  if [ ! -f "$CONFIG_FILE" ]; then
    local src_cfg="${_TMP}/qberry.toml"
    [ -f "$src_cfg" ] || src_cfg="$(find "$_TMP" -maxdepth 3 -type f -name 'qberry.toml' 2>/dev/null | head -n1)"
    if [ -n "${src_cfg:-}" ] && [ -f "$src_cfg" ]; then
      log "Installing default config 🧩: ${CONFIG_FILE}"
      install -m 0644 "$src_cfg" "$CONFIG_FILE"
    fi
  else
    log "Keeping existing config 💾: ${CONFIG_FILE}"
  fi

  patch_config "$CONFIG_FILE"

  # Environment file template (Linux only; macOS uses plist EnvironmentVariables)
  if [ "$os" = "linux" ] && [ ! -f "$ENV_FILE" ]; then
    cat > "$ENV_FILE" <<'EOF'
# qberry-cli systemd environment
QBERRY_LOG_LEVEL=off
EOF
    chmod 0644 "$ENV_FILE"
  fi

  # Runtime shared libraries (Linux only)
  if [ "$os" = "linux" ]; then
    if command -v apt-get >/dev/null 2>&1; then
      if ! ldconfig -p 2>/dev/null | grep -q 'libxcb\.so\.1'; then
        log "Installing runtime libraries 📚: libxcb1 libxcb-shm0 libxcb-randr0"
        apt-get install -y --no-install-recommends libxcb1 libxcb-shm0 libxcb-randr0 2>/dev/null || \
          warn "Could not install XCB libraries — service may fail (exit code 127)"
      fi
    elif command -v dnf >/dev/null 2>&1; then
      dnf install -y libxcb 2>/dev/null || true
    elif command -v yum >/dev/null 2>&1; then
      yum install -y libxcb 2>/dev/null || true
    fi

    # TUN module
    if ! lsmod 2>/dev/null | grep -q '^tun'; then
      modprobe tun 2>/dev/null || warn "Could not enable the tun kernel module"
    fi
  fi

  setup_service "$os"

  local installed_ver
  installed_ver="$("$BIN_PATH" --version 2>/dev/null || true)"
  log "Install complete 🎉: ${installed_ver:-$BIN_PATH}"

  local svc_info
  if [ "$os" = "macos" ]; then
    svc_info="${PLIST_PATH}"
  else
    svc_info="${SERVICE_PATH}"
  fi

  cat <<EOF

  Binary  : ${BIN_PATH}
  Bundle  : ${APP_BUNDLE}
  Config  : ${CONFIG_FILE}
  Service : ${svc_info} ($([ "$NO_SERVICE" = "1" ] && echo skipped || echo installed))

  Quick commands:
EOF

  if [ "$os" = "macos" ]; then
    cat <<EOF
    sudo launchctl list | grep ${PLIST_LABEL}
    sudo launchctl unload ${PLIST_PATH} && sudo launchctl load -w ${PLIST_PATH}
    tail -f /var/log/${SERVICE_NAME}.log

  ⚠️  Two TCC permissions are required for remote desktop:
    System Settings > Privacy & Security > Screen Recording   > enable "QBerry"
    System Settings > Privacy & Security > Accessibility      > "+" /Applications/QBerry.app, enable
    (System Settings should have opened automatically.)

    IMPORTANT:
      - Grant ONLY the "QBerry" app entry. Do NOT add /usr/local/bin/qberry
        (it is a symlink and TCC will not honor it).
      - Restart the service after granting:
          sudo launchctl unload ${PLIST_PATH} && sudo launchctl load -w ${PLIST_PATH}
EOF
  else
    cat <<EOF
    sudo systemctl status ${SERVICE_NAME}
    sudo systemctl restart ${SERVICE_NAME}
    sudo journalctl -u ${SERVICE_NAME} -f
EOF
  fi
}

if [ "$DO_UNINSTALL" = "1" ]; then
  uninstall
else
  install_main
fi
