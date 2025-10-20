# Nerves Deployment Runbook

**Status**: Active  
**Owner**: ThunderGate + ThunderLink Domains  
**Last Updated**: 2025-10-20  
**HC Reference**: HC-23.3 (mTLS Enrollment), HC-23.6 (Firmware Pipeline)

---

## 1. Overview

This runbook covers deploying Thunderline to edge devices using Nerves - the embedded Elixir/Erlang runtime. Nerves devices run autonomous PAC execution locally, enforce Crown policies offline, and backhaul telemetry via TOCP.

**Supported Hardware**:
- Raspberry Pi 4 (4GB+ RAM recommended)
- BeagleBone Black
- Custom embedded Linux (armv7+)

**Key Capabilities**:
- Local PAC execution (offline-capable)
- mTLS enrollment with ThunderGate
- Crown policy caching
- Store-and-forward telemetry
- OTA firmware updates (A/B partitions)
- NIFs for ML inference (TensorFlow Lite), image processing, crypto

---

## 2. Development Environment Setup

### 2.1 Prerequisites

```bash
# Elixir 1.18.0+, Erlang 27.1+
asdf install elixir 1.18.0
asdf install erlang 27.1

# Nerves toolchain
mix archive.install hex nerves_bootstrap

# fwup (firmware utility)
# macOS
brew install fwup squashfs coreutils xz

# Ubuntu/Debian
sudo apt-get install fwup squashfs-tools

# Verify installation
mix nerves.info
```

### 2.2 Create Nerves Project

```bash
# Generate new Nerves project
mix nerves.new thunderline_device
cd thunderline_device

# Set target hardware
export MIX_TARGET=rpi4  # or bbb, rpi3, etc.

# Install dependencies
mix deps.get
```

### 2.3 Integrate Thunderline Client

Add to `mix.exs`:

```elixir
def deps do
  [
    # Nerves dependencies
    {:nerves, "~> 1.10", runtime: false},
    {:shoehorn, "~> 0.9"},
    {:ring_logger, "~> 0.11"},
    
    # Thunderline client
    {:thunderline_client, path: "../thunderline_client"},
    {:jido_signal, "~> 0.1"},
    {:req, "~> 0.5"},
    
    # Hardware targets
    {:nerves_system_rpi4, "~> 1.26", runtime: false, targets: :rpi4}
  ]
end
```

---

## 3. Firmware Build Pipeline

### 3.1 Configuration

`config/target.exs`:

```elixir
config :thunderline_client,
  gateway_url: System.get_env("THUNDERGATE_URL") || "https://gate.thunderline.io",
  device_id: System.get_env("DEVICE_ID"),
  cert_path: "/root/certs/device.pem",
  key_path: "/root/certs/device-key.pem",
  ca_path: "/root/certs/ca.pem"

config :nerves, :firmware,
  rootfs_overlay: "rootfs_overlay",
  provisioning: :nerves_hub  # or custom provisioning
```

### 3.2 Build Firmware

```bash
# Set target
export MIX_TARGET=rpi4

# Build firmware image
mix firmware

# Output: _build/rpi4_dev/nerves/images/thunderline_device.fw
```

### 3.3 Sign Firmware

Crown Ed25519 signing for OTA integrity:

```bash
# Sign with Crown key (server-side)
fwup --sign \
  --private-key priv/crown_signing_key.pem \
  --input _build/rpi4_dev/nerves/images/thunderline_device.fw \
  --output thunderline_device.signed.fw

# Verify signature
fwup --verify \
  --public-key priv/crown_signing_key.pub \
  --input thunderline_device.signed.fw
```

**Key Management**:
- Crown signing key stored in HashiCorp Vault
- Device public keys distributed via ThunderGate
- Rotation policy: 90 days

---

## 4. Device Provisioning

### 4.1 Hardware Preparation

**Raspberry Pi 4**:
1. Obtain 16GB+ microSD card (Class 10 or better)
2. Connect Ethernet (WiFi supported but Ethernet recommended for enrollment)
3. Power supply: 5V 3A USB-C

**BeagleBone Black**:
1. Use 8GB+ microSD or onboard eMMC
2. Ethernet via RJ45
3. Power: 5V 2A barrel jack

### 4.2 Burn Firmware to SD Card

```bash
# macOS
mix firmware.burn

# Linux (specify device)
mix firmware.burn -d /dev/mmcblk0

# Manual with fwup
fwup -a -i thunderline_device.fw -t complete -d /dev/mmcblk0
```

### 4.3 First Boot

1. Insert SD card into device
2. Power on
3. Device boots into Nerves runtime (~30 seconds)
4. Obtains IP via DHCP
5. Starts enrollment sequence

**Check Device IP**:
```bash
# Scan network for device
nmap -p 22 192.168.1.0/24

# SSH into device (if enabled)
ssh nerves@192.168.1.100
# Default password: nerves
```

---

## 5. mTLS Enrollment

### 5.1 Certificate Provisioning

**Pre-Enrollment** (before device ships):

```bash
# Generate device certificate (server-side)
mix thunderline.device.provision \
  --device-id "device-00001" \
  --hardware-id "rpi4-serial-abc123" \
  --output priv/certs/device-00001.pem

# Output:
# - device-00001.pem (certificate)
# - device-00001-key.pem (private key)
# - ca.pem (CA certificate)
```

**Embed in Firmware**:

Copy certs to `rootfs_overlay/root/certs/`:
```
rootfs_overlay/
└── root/
    └── certs/
        ├── device.pem
        ├── device-key.pem
        └── ca.pem
```

Rebuild firmware with embedded certs.

### 5.2 Enrollment Handshake

**5-Step Process** (automatic on first boot):

```elixir
# In application.ex
defmodule ThunderlineDevice.Application do
  def start(_type, _args) do
    children = [
      {ThunderlineClient.Enrollment, [
        gateway_url: gateway_url(),
        cert_path: cert_path(),
        key_path: key_path(),
        ca_path: ca_path()
      ]}
    ]
    
    Supervisor.start_link(children, strategy: :one_for_one)
  end
end
```

**Step 1**: Device presents client certificate  
**Step 2**: ThunderGate validates certificate chain  
**Step 3**: Check revocation status (OCSP)  
**Step 4**: Establish TOCP session via ThunderLink  
**Step 5**: Download Crown policy manifest  

**Event Emitted**: `device.enrolled`

```json
{
  "type": "device.enrolled",
  "source": "/gate/enrollment",
  "data": {
    "device_id": "device-00001",
    "hardware_id": "rpi4-serial-abc123",
    "firmware_version": "1.0.0",
    "enrolled_at": "2025-10-20T15:30:00Z"
  }
}
```

### 5.3 Troubleshooting Enrollment

**Certificate Validation Failures**:
```bash
# Check cert expiration
openssl x509 -in /root/certs/device.pem -noout -dates

# Verify cert chain
openssl verify -CAfile /root/certs/ca.pem /root/certs/device.pem
```

**Network Issues**:
```bash
# Test connectivity
ping gate.thunderline.io

# Check TLS handshake
openssl s_client -connect gate.thunderline.io:443 \
  -cert /root/certs/device.pem \
  -key /root/certs/device-key.pem
```

**Log Analysis**:
```elixir
# Access RingLogger
RingLogger.tail()
RingLogger.grep("enrollment")
```

---

## 6. Policy Manifest Caching

### 6.1 Initial Download

Post-enrollment, device downloads Crown policy manifest:

```elixir
defmodule ThunderlineClient.PolicyCache do
  use GenServer
  
  def init(_) do
    schedule_sync()
    {:ok, %{manifest: nil, last_sync: nil}}
  end
  
  def handle_info(:sync, state) do
    case fetch_manifest() do
      {:ok, manifest} ->
        File.write!("/data/policy_cache.json", Jason.encode!(manifest))
        schedule_sync()
        {:noreply, %{state | manifest: manifest, last_sync: DateTime.utc_now()}}
      {:error, _reason} ->
        # Use cached policy
        manifest = load_cached_manifest()
        schedule_sync()
        {:noreply, %{state | manifest: manifest}}
    end
  end
  
  defp schedule_sync do
    Process.send_after(self(), :sync, :timer.minutes(15))
  end
end
```

**Cache Location**: `/data/policy_cache.json` (persisted across reboots)

### 6.2 Offline Mode

Device operates autonomously when disconnected:
- Evaluates PAC actions against cached policy
- Queues telemetry events locally (SQLite)
- Logs ambiguous policy decisions for server review
- Resumes sync on reconnection

**Event Emitted**: `device.offline`

---

## 7. OTA Firmware Updates

### 7.1 Server-Side Orchestration

ThunderGate triggers OTA update:

```elixir
# Push firmware to device group
mix thunderline.device.update \
  --firmware thunderline_device.signed.fw \
  --group "production-west" \
  --rollout-percentage 10
```

**Rollout Strategy**:
- Canary: 10% of devices
- Monitor for 1 hour
- Gradually increase: 25% → 50% → 100%
- Auto-rollback on failure threshold (>5% failures)

### 7.2 Device-Side A/B Swap

**Update Process** (automatic):

1. Device receives OTA notification via TOCP
2. Downloads firmware to inactive partition (`/dev/mmcblk0p3`)
3. Verifies signature against Crown public key
4. Sets boot flag to new partition
5. Reboots into new firmware
6. Reports success/failure to ThunderGate
7. If failure, auto-rollback to previous partition

**Partition Layout**:
```
/dev/mmcblk0p1  Boot (FAT32)
/dev/mmcblk0p2  Root A (squashfs) - Active
/dev/mmcblk0p3  Root B (squashfs) - Inactive
/dev/mmcblk0p4  Data (ext4) - Persistent
```

**Event Emitted**: `device.firmware.updated`

```json
{
  "type": "device.firmware.updated",
  "source": "/device/ota",
  "data": {
    "device_id": "device-00001",
    "old_version": "1.0.0",
    "new_version": "1.1.0",
    "partition": "B",
    "updated_at": "2025-10-20T16:00:00Z"
  }
}
```

### 7.3 Rollback

Manual rollback (if needed):

```bash
# SSH into device
ssh nerves@device-ip

# Check current partition
cat /proc/cmdline | grep root=

# Reboot to previous partition
fwup --revert -d /dev/mmcblk0
reboot
```

---

## 8. Device Management

### 8.1 View Enrolled Devices

```elixir
# List all devices
devices = Thunderline.Gate.list_devices()

# Query specific device
device = Thunderline.Gate.get_device!("device-00001")

# Output:
# %Device{
#   id: "device-00001",
#   hardware_id: "rpi4-serial-abc123",
#   firmware_version: "1.1.0",
#   last_heartbeat: ~U[2025-10-20 16:05:00Z],
#   status: :online,
#   enrolled_at: ~U[2025-10-20 15:30:00Z]
# }
```

### 8.2 Force Re-Enrollment

```bash
# Revoke device certificate
mix thunderline.device.revoke --device-id "device-00001"

# Device detects revocation on next heartbeat
# Automatically initiates re-enrollment with new cert
```

### 8.3 Certificate Rotation

**Policy**: Rotate every 90 days

```bash
# Generate new cert for device
mix thunderline.device.rotate-cert \
  --device-id "device-00001" \
  --output priv/certs/device-00001-new.pem

# Push via OTA config update (not full firmware)
mix thunderline.device.push-config \
  --device-id "device-00001" \
  --cert priv/certs/device-00001-new.pem
```

### 8.4 Decommission Device

```bash
# Mark device as decommissioned
mix thunderline.device.decommission --device-id "device-00001"

# Revoke certificate
mix thunderline.device.revoke --device-id "device-00001"

# Device will fail next enrollment attempt
```

---

## 9. Troubleshooting

### 9.1 Common Issues

**Device Not Enrolling**:
- Check certificate validity: `openssl x509 -in device.pem -noout -dates`
- Verify network connectivity: `ping gate.thunderline.io`
- Check ThunderGate logs for rejection reason
- Ensure device clock is accurate (NTP sync)

**Heartbeat Not Received**:
- Check device online status: `mix thunderline.device.status --device-id "device-00001"`
- Verify TOCP session active: `RingLogger.grep("tocp")`
- Network firewall blocking outbound 443/8883?

**OTA Update Failed**:
- Check firmware signature: `fwup --verify --public-key crown.pub --input firmware.fw`
- Review device logs: `RingLogger.grep("ota")`
- Insufficient storage on inactive partition?
- Manual rollback: `fwup --revert -d /dev/mmcblk0`

**Policy Evaluation Errors**:
- Check cached manifest: `cat /data/policy_cache.json | jq`
- Review Crown policy syntax on server
- Device may be in offline mode (expected behavior)

### 9.2 Log Analysis

**Access Device Logs**:
```elixir
# Via SSH
ssh nerves@device-ip
iex> RingLogger.tail(100)
iex> RingLogger.grep("error")
iex> RingLogger.attach()  # Real-time streaming
```

**Key Log Patterns**:
- `[Enrollment]` - mTLS handshake events
- `[PolicyCache]` - Manifest sync/cache hits
- `[TOCP]` - Telemetry backhaul
- `[OTA]` - Firmware update progress

### 9.3 Network Debugging

```bash
# Check DHCP lease
ip addr show eth0

# DNS resolution
nslookup gate.thunderline.io

# TLS handshake
openssl s_client -connect gate.thunderline.io:443

# MQTT (TOCP) connection
mosquitto_sub -h link.thunderline.io -p 8883 \
  --cert device.pem --key device-key.pem --cafile ca.pem \
  -t "device/device-00001/telemetry"
```

---

## 10. Reference

### 10.1 Sample Project Structure

```
thunderline_device/
├── config/
│   ├── config.exs
│   ├── host.exs
│   └── target.exs
├── lib/
│   ├── thunderline_device.ex
│   └── thunderline_device/
│       ├── application.ex
│       ├── enrollment.ex
│       └── policy_cache.ex
├── rootfs_overlay/
│   └── root/
│       └── certs/
│           ├── device.pem
│           ├── device-key.pem
│           └── ca.pem
├── mix.exs
└── README.md
```

### 10.2 Configuration Examples

**Enrollment Config**:
```elixir
config :thunderline_client, ThunderlineClient.Enrollment,
  gateway_url: "https://gate.thunderline.io",
  device_id: {:system, "DEVICE_ID"},
  cert_path: "/root/certs/device.pem",
  key_path: "/root/certs/device-key.pem",
  ca_path: "/root/certs/ca.pem",
  retry_backoff: [500, 1000, 2000, 5000],
  heartbeat_interval: :timer.minutes(5)
```

**TOCP Config**:
```elixir
config :thunderline_client, ThunderlineClient.TOCP,
  broker_url: "mqtts://link.thunderline.io:8883",
  client_id: {:system, "DEVICE_ID"},
  topics: ["device/+/telemetry", "device/+/control"],
  qos: 1,
  keepalive: 60,
  reconnect_delay: :timer.seconds(10)
```

### 10.3 Command Cheatsheet

```bash
# Build
export MIX_TARGET=rpi4
mix deps.get
mix firmware

# Burn to SD
mix firmware.burn

# Sign firmware
fwup --sign --private-key crown.pem -i firmware.fw -o firmware.signed.fw

# Device provisioning
mix thunderline.device.provision --device-id "device-00001"

# View devices
mix thunderline.device.list

# Trigger OTA
mix thunderline.device.update --firmware firmware.signed.fw --group "prod"

# Revoke cert
mix thunderline.device.revoke --device-id "device-00001"

# Decommission
mix thunderline.device.decommission --device-id "device-00001"
```

---

## 11. Cross-References

- **HC-23.3**: mTLS Enrollment Architecture
- **HC-23.6**: Firmware Build Pipeline
- **EVENT_TAXONOMY.md**: `device.*` event definitions
- **DOMAIN_CATALOG.md**: Gate (enrollment), Link (TOCP), Crown (policies)
- **THUNDERLINE_MASTER_PLAYBOOK.md**: HC-23 Nerves Runtime section

---

**Deployment Checklist**:
- [ ] Nerves toolchain installed
- [ ] Device certificates generated
- [ ] Firmware built and signed
- [ ] SD card burned
- [ ] Device enrolled successfully
- [ ] Heartbeat events received
- [ ] Policy manifest cached
- [ ] OTA update tested (dev environment)
- [ ] Rollback procedure verified
- [ ] Monitoring dashboards configured

**Next Steps**: Update THUNDERLINE_ARCHITECTURE.md with multi-dimensional VM design (Thundra).
