# Finch Mobile — RF Engagement Platform (Glass Fabric 2.0)

Standalone iOS 17+ app for **authorized** on-device BLE radar, LAN IoT assessment, multi-sensor track fusion, drone-class detection, and consent-gated active-ops auditing. No backend. Apple frameworks only.

**Version 2.0 — RF Platform:** fused tracks · threat scoring · AR overlay · drone module · consent/arm · forensic chain · Multipeer mesh · research playbooks.

## Tabs

| Tab | Capability |
|-----|------------|
| **Engage** | CIDR / private IP → Glass Fabric (subnet sweep, mDNS, SSDP, deep ports, offense probes, banners, fingerprints, MQTT listen, SENTINEL export). |
| **Nearby** | Continuous CoreBluetooth scan + Connect / GATT map / characteristic **read**. |
| **Tracks** | Multi-source fusion (BLE + Glass hosts + synthetic/mesh) with 1–10 threat scores. |
| **Drone** | Passive drone/controller classification; Observe MAVLink surfaces; active ops are **consent-gated** and do **not** Tx on stock iOS. |
| **Command** | Map, AR overlay, Consent/Arm, Forensic export, Vault, Settings, Mesh, Research Mode, Playbooks. |

## Honest capability matrix

| Feature | Stock iPhone |
|---------|--------------|
| BLE scan / GATT read | Yes |
| LAN IoT / MQTT listen | Yes |
| Track fusion + threat score | Yes |
| AR reticles for tracks | Yes (ARKit devices) |
| Forensic SHA-256 chain export | Yes |
| Consent token + kill switch | Yes |
| Mesh share of track summaries | Yes (Multipeer) |
| Research Mode synthetic inject | Yes |
| SDR / RF capture / replay | Needs external SDR |
| BLE write / MITM / clone | Not implemented (read-only) |
| MAVLink command / GPS spoof / jam | Consent + external authorized kit only — app audits, does not transmit |

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
