#!/bin/bash

# QKEY Server Installation Script
# Run as root: sudo ./install-qkey.sh

#set -e
systemctl stop qkey-server

# Check Rust installed
if ! command -v cargo &> /dev/null; then
    echo "Rust/Cargo not found. Install from https://rustup.rs/"
    #exit 1
fi

# Build
cargo build --release

# Install binary
strip target/release/qkey
cp target/release/qkey /usr/bin/qkey
cargo clean

# Create systemd service (paste the content from above)
cat <<EOT > /etc/systemd/system/qkey-server.service
[Unit]
Description=QKEY Server
After=network.target

[Service]
Type=simple
ExecStart=/usr/bin/qkey --gateway
User=root
Group=root
Restart=always
RestartSec=5
Environment="RUST_LOG=off"

[Install]
WantedBy=multi-user.target
EOT

# Reload and enable
systemctl daemon-reload
systemctl enable qkey-server
systemctl start qkey-server

echo "Installation complete. Check status: systemctl status qkey-server"
