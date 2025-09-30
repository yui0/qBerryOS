# QKEY
A lightweight VPN built in Rust, using TUN devices for secure UDP communication on Linux, Windows, macOS, Android, and iOS.

## Overview
QKEY is a secure VPN server and client implementation that leverages the `tun-rs` library for cross-platform TUN device support. It employs X25519 for key exchange, AES-256-GCM or ChaCha20-Poly1305 for encryption, and optional ML-KEM-768+ChaCha20-Poly1305 for post-quantum cryptography (PQC) hybrid encryption. The VPN supports both IPv4 and IPv6, with configurable MTU, heartbeat mechanisms, packet fragmentation, LZ4 compression, and optional internet connectivity for robust and flexible networking. The server also includes a web-based admin dashboard for monitoring connected clients, with Prometheus metrics integration for observability. Rate limiting is applied using a token bucket algorithm to manage upload bandwidth.

## Features
- **Cross-Platform**: Supports Linux, Windows, macOS, Android, and iOS.
- **Secure Communication**: Uses X25519 key exchange, AES-256-GCM or ChaCha20-Poly1305 encryption, and optional ML-KEM-768 for PQC hybrid encryption.
- **IPv4/IPv6 Support**: Configurable via command-line arguments.
- **Heartbeat Mechanism**: Ensures client-server connectivity with a configurable interval (default: 180 seconds) and 300-second timeout.
- **Packet Fragmentation and Reassembly**: Handles large packets by fragmenting them into smaller chunks (up to 255 fragments) with timeout handling (60 seconds).
- **LZ4 Compression**: Compresses packet payloads for efficient transmission using LZ4.
- **TUN Device**: Automatically configures virtual network interfaces.
- **Scalable**: Supports up to 100 clients by default.
- **Cryptographic Flexibility**: Supports multiple encryption algorithms (AES-256-GCM, ChaCha20-Poly1305, ML-KEM-768+ChaCha20-Poly1305).
- **Internet Connectivity**: Optional internet access via `--vpn-proxy` flag, enabling IP forwarding, NAT, and DNS configuration.
- **Admin Dashboard**: Web interface for server monitoring, showing connected clients, virtual IPs, last heartbeat times, and configuration updates.
- **Ad Blocking**: Optional ad blocking feature to filter unwanted traffic (enabled by default, using `blocklist.txt`).
- **Prometheus Metrics**: Exposes metrics for bytes sent/received, peer count, and HTTP requests at `/metrics`.
- **Rate Limiting**: Token bucket-based upload rate limiting (default: 50 Mbps).
- **Peer Sharing**: Automatically shares peer lists for mesh networking.
- **Gateway Mode**: Supports `--gateway` for designating nodes as gateways.
- **Initial Peers**: Connect to multiple initial peers via `--initial-peers` for mesh setup.

## Prerequisites

### Linux
- **Install Network Tools**:
  ```bash
  sudo apt update
  sudo apt install build-essential
  sudo apt install iproute2 iptables
  ```
- **Verify TUN/TAP kernel module**: `lsmod | grep tun`. If missing, enable it via your distribution's documentation.
- **Install Rust and Cargo**:
  ```bash
  curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh
  cargo install cross
  rustup target list | grep windows
  cross build --target x86_64-pc-windows-gnu
  ```

### Windows
- **Install git**:
  - Download and install git from [Git for Windows](https://gitforwindows.org/).
- **Install Rust and Cargo**:
  - Download and run the `rustup-init.exe` installer from [rustup.rs](https://rustup.rs).
  - Follow the installer prompts, selecting the default installation option (enter `1` when prompted).
  - The installer adds `cargo` and other tools to `%USERPROFILE%\.cargo\bin` and updates the system PATH.
  - Run the installer as Administrator if you encounter permission issues during QKEY execution.
  - Verify the installation:
    ```bash
    cargo --version
    ```
    Expect output like `cargo 1.x.x`, confirming a successful installation.
- **Install wintun**:
  - Download and install wintun to same directory of qkey.
- **Run as Administrator**: Required for TUN device operations.
- https://vimeo.com/1121188484?share=copy

### macOS
- **Install Rust and Cargo**:
  ```bash
  curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh
  ```
- **Privileges**: Run with `sudo` for TUN device operations.

### Android / iOS
- Supported via `tun-rs` but requires integration with platform-specific APIs (e.g., `VpnService` on Android, `Network Extension` on iOS). The provided code is a command-line tool and needs mobile app wrapping for direct use.

### Common Requirements
- **Privileges**: Requires `sudo` on Linux/macOS or Administrator on Windows. Mobile platforms need specific permissions.
- **Firewall**: Allow UDP traffic on the chosen port (default: 8090) and TCP for the web port (default: 8080).
- **Dependencies**: Ensure `ring`, `tun-rs`, `actix-web`, `prometheus`, and `saorsa_pqc` are available via Cargo.

## Installation
1. Clone the repository:
   ```bash
   git clone <repository-url>
   cd qkey
   ```
2. Build the project:
   ```bash
   cargo build --release
   ```

## Running the VPN
The application is a single binary that operates in peer mode, supporting mesh networking. Use `--initial-peers` to connect to existing peers. Configuration is via CLI arguments or `config.toml`.

### Start a Peer
Run with default settings (port 8090, interface `tun0`) or customize:
```bash
# Linux / macOS
sudo ./target/release/qkey --listen-port 8090 --interface-name tun0 --mtu 1420 --heartbeat-secs 180 --max-peers 100 --ipv6 false --crypto-alg Aes256Gcm --vpn-proxy true --gateway false --web true --web-port 8080 --ad-block true --initial-peers <peer1:port>,<peer2:port>
# Windows (run as Administrator)
./target/release/qkey.exe --listen-port 8090 --interface-name tun0 --mtu 1420 --heartbeat-secs 180 --max-peers 100 --ipv6 false --crypto-alg Aes256Gcm --vpn-proxy true --gateway false --web true --web-port 8080 --ad-block true --initial-peers <peer1:port>,<peer2:port>
```

**Options**:
- `--listen-port`: UDP port for listening (default: 8090).
- `--interface-name`: TUN interface name (default: `tun0`).
- `--mtu`: Maximum transmission unit (default: 1420).
- `--heartbeat-secs`: Heartbeat interval (default: 180 seconds).
- `--max-peers`: Maximum number of peers (default: 100).
- `--ipv6`: Enable IPv6 (default: `false`).
- `--crypto-alg`: Encryption algorithm (default: `Aes256Gcm`). Options: `Aes256Gcm`, `ChaCha20Poly1305`, `MlKem768ChaCha20`.
- `--vpn-proxy`: Enable internet connectivity via IP forwarding and NAT (default: `true`).
- `--gateway`: Designate this peer as a gateway (default: `false`).
- `--web`: Enable web dashboard (default: `true`).
- `--web-port`: TCP port for the admin dashboard (default: 8080).
- `--ad-block`: Enable ad blocking (default: `true`).
- `--initial-peers`: Comma-separated list of initial peers to connect to (e.g., `192.168.1.100:8090,example.com:8090`).

### Admin Dashboard
The web-based dashboard is accessible at `http://<local-ip>:<web-port>/` (default: `http://localhost:8080/`). It displays:
- App state (listen port, interface name, MTU, IPv6, VPN proxy, web port, ad block).
- Connected peers table with address, virtual IPv4/IPv6, last heartbeat, connected duration, bytes sent/received, and gateway status.
- Options to connect/disconnect peers, update config, update ad block list, and view logs.

Ensure the firewall allows TCP traffic on the web port. Metrics are available at `/metrics`.

## Actions Confirmation
To verify the VPN functionality:

### Compile the Code
Build the single binary:
```bash
cargo build --release
```

### Start a Gateway Peer
Run with VPN proxy and ad blocking enabled:
```bash
sudo ./target/release/qkey --listen-port 8090 --interface-name tun0 --mtu 1420 --ipv6 false --crypto-alg Aes256Gcm --vpn-proxy true --gateway true --web true --web-port 8080 --ad-block true
```
**Expected output**:
```
[INFO] QKEY by Yuichiro Nakada and Applied Robot Co., Ltd.
[INFO] Starting QKEY: MTU: 1420, IPv6: false, Mesh Proxy: true, Web UI: 8080, Ad Block: true, Initial Peers: [], Gateway: true
[INFO] TUN interface created: tun0. Local IP: 10.0.0.1/24
[INFO] Listening on UDP port 8090
```
- If `tun0` is unavailable, it tries `tun1`, etc.
- Verify TUN interface:
  ```bash
  ip addr show tun0  # Linux
  ifconfig tun0      # macOS
  ipconfig           # Windows (look for TAP adapter)
  ```
- Verify NAT (Linux):
  ```bash
  iptables -t nat -L
  ```
- Access the dashboard: Open `http://localhost:8080/` in a browser.

### Start a Client Peer
Connect to the gateway:
```bash
sudo ./target/release/qkey --listen-port 8090 --interface-name tun0 --mtu 1420 --ipv6 false --crypto-alg Aes256Gcm --vpn-proxy true --gateway false --web true --web-port 8080 --ad-block true --initial-peers 127.0.0.1:8090
```
- Replace `127.0.0.1` with the gateway’s actual IP for remote setups.
- **Expected output**:
  ```
  [INFO] Starting QKEY: MTU: 1420, IPv6: false, Mesh Proxy: true, Web UI: 8080, Ad Block: true, Initial Peers: ["127.0.0.1:8090"], Gateway: false
  [INFO] TUN interface created: tun0
  [INFO] Connected to peer 127.0.0.1:8090
  [INFO] Assigned virtual IP: IPv4: 10.0.0.2, IPv6: None
  ```
- Verify TUN interface:
  ```bash
  ip addr show tun0  # Linux
  ```

### Test Connectivity
- **Ping Test (VPN Tunnel)**:
  From the client, ping the gateway’s virtual IP:
  ```bash
  ping 10.0.0.1  # IPv4
  ping6 fd00::1  # IPv6 (if enabled)
  ```
  Expect responses.

- **Internet Connectivity Test** (if `--vpn-proxy` is used):
  Test internet access:
  ```bash
  ping 8.8.8.8
  curl https://www.example.com
  ```
  Verify DNS resolution:
  ```bash
  nslookup google.com
  ```

- **Packet Capture (optional)**:
  Verify encrypted UDP traffic:
  ```bash
  sudo tcpdump -i any udp port 8090  # Linux
  ```

- **Route Verification**:
  Check client routing table:
  ```bash
  ip route  # Linux
  ```
  Confirm default route via gateway.

### Test IPv6 Support
- Add `--ipv6 true` to commands and test with `ping6`.

### Test Post-Quantum Cryptography
- Use `--crypto-alg MlKem768ChaCha20` and verify logs for PQC usage.

### Test Heartbeat
- Monitor logs for heartbeat messages.

### Test Fragmentation and Compression
- Send large packets (e.g., `ping -s 2000 10.0.0.1`) and verify fragmentation in logs.

### Test Metrics
- Access `http://localhost:8080/metrics` for Prometheus data.

### Success Criteria
- Peers connect without errors.
- TUN interfaces created.
- Virtual IPs assigned.
- Ping and internet access succeed.
- Dashboard shows peers.
- Metrics exposed.
- Ad blocking filters traffic.

## Logging
Enable detailed logs:
```bash
RUST_LOG=info ./target/release/qkey --listen-port 8090
```

## Troubleshooting
- **TUN Device Errors**: Ensure privileges, check conflicts.
- **UDP Errors**: Verify port open, firewall.
- **Web Dashboard Errors**: Check port, firewall.
- **No Ping Response**: Confirm routing, firewall.
- **No Internet Access**: Verify NAT, default route, DNS.
- **PQC Errors**: Check `saorsa_pqc` dependency.
- **Rate Limiting Issues**: Adjust upload limits if needed.

## How It Works
- **Peers**: All nodes are peers in a mesh; gateways provide internet access.
- **Encryption**: X25519 + chosen alg, with PQC option.
- **Compression/Fragmentation**: LZ4 + custom headers.
- **TUN Device**: Via `tun-rs`.
- **Heartbeat**: Every 180s, timeout 300s.
- **Ad Blocking**: Filters via `blocklist.txt`.
- **Metrics**: Prometheus for monitoring.

## Notes
- **Virtual IPs**: `10.0.0.1/24` (IPv4), `fd00::1/64` (IPv6).
- **Production**: Add auth to dashboard, harden against DoS.
- **Security**: Replay protection, secure RNG.
- **Limitations**: Mobile needs wrapping; max 255 fragments.
- **Updates**: Checks for updates at startup via `update.rs`.
