# Finch Mobile — THE MACHINE (OSINT + Glass Fabric 3.0)

Standalone iOS 17+ app for **authorized** on-device OSINT (identity, address, plate, cyber, web3), BLE radar, LAN IoT assessment, multi-sensor track fusion, and drone-class detection. No laptop backend. Apple frameworks only + public APIs.

**Version 3.2 (build 35):** Engage seed router like desktop Finch · OSINT lattice · Glass Fabric · Nearby BLE. Passive / read-only on stock iPhone.

## Tabs

| Tab | Capability |
|-----|------------|
| **Engage** | Seed bar like desktop Finch: name / email / phone / @handle / address / plate / domain / IP / `0x…` / CIDR. OSINT rails hit public APIs on-device; Glass Fabric for LAN. |
| **Nearby** | Continuous CoreBluetooth scan + Connect / GATT map / characteristic **read**. |
| **Tracks** | Multi-source fusion (BLE + Glass hosts + synthetic/mesh) with 1–10 threat scores. |
| **Drone** | Passive drone/controller classification; Observe MAVLink surfaces; active ops are **consent-gated** and do **not** Tx on stock iOS. |
| **Command** | Map, AR overlay, Consent/Arm, Forensic export, Vault, Settings, Mesh, Research Mode, Playbooks. |

## Honest capability matrix

| Feature | Stock iPhone |
|---------|--------------|
| Identity / email / @handle OSINT | Yes (public APIs; HIBP needs key) |
| Address geocode + Census | Yes (no DMV / paid assessor scrape) |
| Plate / VIN (NHTSA) | Yes (no DMV) |
| Domain / IP cyber (DoH, CT, RDAP, InternetDB) | Yes (Shodan host needs key) |
| Web3 ETH balance | Yes (Etherscan txs need key) |
| BLE scan / GATT read | Yes |
| LAN IoT / MQTT listen | Yes |
| Track fusion + threat score | Yes |
| SDR / RF capture / replay | Needs external SDR |
| BLE write / MITM / clone | Not implemented (read-only) |
| MAVLink Tx / jam / GPS spoof | Not on stock iOS |

## Requirements

- Xcode 15+ / iOS 17+
- Physical iPhone
- Authorization to assess the target environment

## Build unsigned IPA (Mac / CI)

```bash
bash BUILD_UNSIGNED_IPA.sh
```

Then **3uTools → Toolbox → IPA Signature** with your Apple ID → install the **signed** IPA. Trust the developer cert on the phone.

Cloud Mac path: **[MAC_CLOUD_SETUP.md](MAC_CLOUD_SETUP.md)** · Windows path: **[WINDOWS_TO_IPHONE.md](WINDOWS_TO_IPHONE.md)**

## Legal

Use only on networks and devices you own or are explicitly authorized to assess. Passive-by-default; active engagement requires a signed consent token, disengaged kill switch, arm, and operator confirmation.
