# Finch Mobile — Glass Fabric (BLE + IoT Red Team)

Standalone iOS 17+ app for **authorized** on-device BLE radar and local-network IoT assessment. No backend. Apple frameworks only.

## Scope

| Tab | Capability |
|-----|------------|
| **Engage** | CIDR / private IP → Glass Fabric (subnet sweep, mDNS, deep ports, banners, fingerprints, MQTT listen, SENTINEL export). `scan ble` / `ble radar` → BLE radar. |
| **BLE Radar** | Continuous CoreBluetooth scan (`AllowDuplicates`), live RSSI + manufacturer data while moving. |
| **Vault** | Ephemeral by default; Persist → AES-256-GCM + SwiftData; Face ID / Touch ID gate. |
| **Settings** | Continuous-scan defaults, vault passphrase / clear vault, fingerprint DB note. |

**Not included:** Identity, Property, Plate, Cyber, Web3 pipelines.

## Requirements

- Xcode 15+ / iOS 17+
- Physical iPhone (BLE + local network scanning do not work fully in Simulator)
- Authorization to scan the target LAN / RF environment

## Open & Build (Mac / MacinCloud)

**Cloud Mac one-liner path:** see **[MAC_CLOUD_SETUP.md](MAC_CLOUD_SETUP.md)**  
Repo: https://github.com/rockstars4nny-hub/FinchMobile

1. Open `FinchMobile.xcodeproj` in Xcode 15+.
2. **Signing & Capabilities** → choose your Apple ID Team.
3. Select your **physical iPhone** → Run (`Cmd+R`), or Archive → export `.ipa` for Sideloadly.
4. Trust the developer cert on the phone: **Settings → General → VPN & Device Management**.

## Windows PC → iPhone

Your Dell **cannot compile** iOS apps (no Xcode on Windows). Keep the source on the Inspiron; use a Mac or cloud Mac only to install.

**Practical path:** see **[WINDOWS_TO_IPHONE.md](WINDOWS_TO_IPHONE.md)** — cloud Mac / borrow a Mac / GitHub Actions.

Short version:

1. Push this folder to GitHub from Windows (or zip it).
2. On any Mac (rented cloud Mac is fine): clone → open project → sign with your Apple ID → Run on the iPhone.
3. Free Apple ID works for personal installs (re-sign about every 7 days). Paid Developer account unlocks TestFlight.

## Permissions (Info.plist)

- `NSBluetoothAlwaysUsageDescription` — live BLE radar in motion  
- `NSLocalNetworkUsageDescription` — LAN / IoT discovery  
- `NSBonjourServices` — `_http._tcp`, `_hap._tcp`, `_mqtt._tcp`, `_rtsp._tcp`, `_companion-link._tcp`, `_printer._tcp`, `_scanner._tcp`, `_dacp._tcp`, `_raop._tcp`  
- `NSFaceIDUsageDescription` — vault unlock  

## Glass Fabric flow

1. Enter `192.168.1.0/24` (or tap **Scan My Network**) → Engage.  
2. Live host list fills from TCP probe + mDNS merge + OUI vendor.  
3. **Deep Scan** on a host (or Deep Scan All) → ~56 IoT ports + banner grab + fingerprint.  
4. If MQTT ports open → **Listen MQTT** (subscribe `#`, max 60s, no publish).  
5. **SENTINEL Export** → JSON/CSV share sheet.  
6. **Persist** → encrypted Vault item.

## BLE Radar

- Background queue `CBCentralManager`  
- `scanForPeripherals(withServices: nil, options: [AllowDuplicates: true])`  
- 30s continuous windows with 1s restart (or Continuous toggle)  
- Device row: short UUID, name, RSSI, manufacturer, services, last seen  

## Design

- Background `#0D0D0D`, accent `#00FFD1`, Menlo / SF Mono for data  
- No third-party packages  

## Legal

Use only on networks and devices you own or are explicitly authorized to assess.
