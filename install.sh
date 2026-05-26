#!/usr/bin/env bash
# QBerry🫐 (qberry-cli) — Linux curl+bash installer ✨
#
# Usage:
#   curl -fsSL https://raw.githubusercontent.com/yui0/qBerryOS/master/install.sh | sudo bash
#   curl -fsSL https://raw.githubusercontent.com/yui0/qBerryOS/master/install.sh | sudo bash -s -- --gateway
#   curl -fsSL https://raw.githubusercontent.com/yui0/qBerryOS/master/install.sh | sudo bash -s -- --version 2026.5.14
#   curl -fsSL https://raw.githubusercontent.com/yui0/qBerryOS/master/install.sh | sudo bash -s -- --uninstall
#
# Options:
#   --version <tag>   Release tag to install (default: latest)
#   --prefix  <dir>   Install prefix (default: /usr/local)
#   --gateway         Add `--gateway` to systemd ExecStart
#   --no-service      Do not configure a systemd service
#   --no-start        Do not enable / start the service
#   --uninstall       Remove binary and service (keep config files)
#
# Equivalent environment variables:
#   QFKEY_VERSION, QFKEY_PREFIX, QFKEY_GATEWAY=1, QFKEY_NO_SERVICE=1, QFKEY_NO_START=1
set -euo pipefail

REPO="yui0/qBerryOS"
BIN_NAME="qberry-cli"
SERVICE_NAME="qberry"
STATE_DIR="/var/lib/${BIN_NAME}"
CONFIG_FILE="/etc/qberry.toml"
ENV_FILE="/etc/qberry.env"

VERSION="${QFKEY_VERSION:-latest}"
PREFIX="${QFKEY_PREFIX:-/usr/local}"
GATEWAY="${QFKEY_GATEWAY:-0}"
NO_SERVICE="${QFKEY_NO_SERVICE:-0}"
NO_START="${QFKEY_NO_START:-0}"
DO_UNINSTALL=0

log()  { printf '\033[1;34m==>\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[!]\033[0m %s\n' "$*" >&2; }
die()  { printf '\033[1;31m[x]\033[0m %s\n' "$*" >&2; exit 1; }

while [ $# -gt 0 ]; do
  case "$1" in
    --version)    VERSION="${2:?--version requires a value}"; shift 2 ;;
    --version=*)  VERSION="${1#*=}"; shift ;;
    --prefix)     PREFIX="${2:?--prefix requires a value}"; shift 2 ;;
    --prefix=*)   PREFIX="${1#*=}"; shift ;;
    --gateway)    GATEWAY=1; shift ;;
    --no-service) NO_SERVICE=1; shift ;;
    --no-start)   NO_START=1; shift ;;
    --uninstall)  DO_UNINSTALL=1; shift ;;
    -h|--help)    sed -n '2,19p' "$0"; exit 0 ;;
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

uninstall() {
  require_root
  log "Uninstalling qberry-cli 🧹"
  if systemctl list-unit-files 2>/dev/null | grep -q "^${SERVICE_NAME}.service"; then
    systemctl stop    "${SERVICE_NAME}" 2>/dev/null || true
    systemctl disable "${SERVICE_NAME}" 2>/dev/null || true
  fi
  rm -f "${SERVICE_PATH}"
  systemctl daemon-reload 2>/dev/null || true
  rm -f "${BIN_PATH}"
  # Clean up legacy binaries that may remain in other prefixes
  rm -f "/usr/bin/${BIN_NAME}" "/usr/local/bin/${BIN_NAME}"
  log "Uninstall complete ✅ (kept ${CONFIG_FILE}, ${ENV_FILE}, and state dir ${STATE_DIR})"
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

resolve_download_url() {
  local arch="$1" version="$2" asset="qberry-cli-linux-${arch}.tar.gz"
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

write_service() {
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

install_main() {
  require_root
  require_cmd tar
  require_cmd uname

  local arch url tmp tarball
  arch="$(detect_arch)"
  url="$(resolve_download_url "$arch" "$VERSION")"

  log "Target: linux-${arch} / version: ${VERSION}"
  log "Downloading 📦: ${url}"

  tmp="$(mktemp -d)"
  trap 'rm -rf "$tmp"' EXIT
  tarball="${tmp}/${BIN_NAME}.tar.gz"
  download "$url" "$tarball"

  log "Extracting archive... ✨"
  tar -xzf "$tarball" -C "$tmp"

  # Archive is expected to include ./qberry-cli and ./qberry.toml
  local src_bin="${tmp}/${BIN_NAME}"
  [ -f "$src_bin" ] || src_bin="$(find "$tmp" -maxdepth 3 -type f -name "${BIN_NAME}" -perm -u+x 2>/dev/null | head -n1)"
  [ -n "${src_bin:-}" ] && [ -f "$src_bin" ] || die "Could not find ${BIN_NAME} in the archive"

  log "Installing 🚀: ${BIN_PATH}"
  install -d -m 0755 "$BIN_DIR"
  install -m 0755 "$src_bin" "$BIN_PATH"

  install -d -m 0755 "$STATE_DIR"

  # Default config file: keep existing file if already present
  if [ ! -f "$CONFIG_FILE" ]; then
    local src_cfg="${tmp}/qberry.toml"
    [ -f "$src_cfg" ] || src_cfg="$(find "$tmp" -maxdepth 3 -type f -name 'qberry.toml' 2>/dev/null | head -n1)"
    if [ -n "${src_cfg:-}" ] && [ -f "$src_cfg" ]; then
      log "Installing default config 🧩: ${CONFIG_FILE}"
      install -m 0644 "$src_cfg" "$CONFIG_FILE"
    fi
  else
    log "Keeping existing config 💾: ${CONFIG_FILE}"
  fi

  # Environment file template
  if [ ! -f "$ENV_FILE" ]; then
    cat > "$ENV_FILE" <<'EOF'
# qberry-cli systemd environment
RUST_LOG=off
EOF
    chmod 0644 "$ENV_FILE"
  fi

  # TUN module
  if ! lsmod 2>/dev/null | grep -q '^tun'; then
    modprobe tun 2>/dev/null || warn "Could not enable the tun kernel module"
  fi

  if [ "$NO_SERVICE" = "1" ]; then
    log "Skipping systemd setup because --no-service was specified 💤"
  elif ! command -v systemctl >/dev/null 2>&1; then
    warn "Skipping systemd setup because systemctl was not found"
  else
    write_service
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

  local installed_ver
  installed_ver="$("$BIN_PATH" --version 2>/dev/null || true)"
  log "Install complete 🎉: ${installed_ver:-$BIN_PATH}"
  cat <<EOF

  Binary  : ${BIN_PATH}
  Config  : ${CONFIG_FILE}
  Service : ${SERVICE_PATH} ($([ "$NO_SERVICE" = "1" ] && echo skipped || echo installed))

  Quick commands:
    sudo systemctl status ${SERVICE_NAME}
    sudo systemctl restart ${SERVICE_NAME}
    sudo journalctl -u ${SERVICE_NAME} -f
EOF
}

if [ "$DO_UNINSTALL" = "1" ]; then
  uninstall
else
  install_main
fi
