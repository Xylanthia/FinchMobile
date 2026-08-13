# Finch Mobile 2.0 — Operator Manual

**App:** Finch (display name) · **Bundle version:** 2.0 (build 20)  
**Platform:** iOS 17+ · physical iPhone only  
**Scope:** Authorized assessments on networks/devices you own or have written permission to test

This is the day-one manual for the new RF Engagement / Glass Fabric 2.0 build. Desktop Finch (OSINT console) is a separate product — this guide is phone-only.

---

## 1. What it is

Finch Mobile is an **offline-first** iOS app for:

- Continuous **BLE** radar (scan + connect + GATT **read**)
- **Glass Fabric** LAN IoT assessment (subnet sweep, mDNS, SSDP, deep ports, banners, fingerprints, MQTT listen, SENTINEL export)
- **Multi-source track fusion** with 1–10 threat scores
- **Drone-class** passive detection / classify
- **Consent / arm / kill-switch** gates for any “active” path
- **Forensic** SHA-256 event chain + export
- Optional **AES-256-GCM Vault**, Multipeer **mesh**, **AR** overlays, **Research Mode** synthetics

It does **not** transmit RF (jam, GPS spoof, MAVLink Tx, BLE write/MITM) on a stock iPhone. Those paths are consent-gated stubs that audit intent and require external authorized kit.

---

## 2. Install once

1. Sideload the signed IPA (3uTools **Toolbox → IPA Signature**, or Xcode on a Mac). See `WINDOWS_TO_IPHONE.md` / `MAC_CLOUD_SETUP.md`.
2. On the phone: **Settings → General → VPN & Device Management** → trust the developer cert.
3. Open **Finch** and allow when prompted:
   - **Bluetooth**
   - **Local Network**
   - **Location** (While Using) — map / distance
   - **Camera** — only if you use AR Overlay
   - **Face ID** — only if you use Vault
4. Prefer a free Personal Team re-sign every ~7 days if you are not on a paid Apple Developer account.

---

## 3. First 60 seconds (safe default)

1. Open Finch → you land on five tabs: **Engage · Nearby · Tracks · Drone · Command**.
2. Kill switch starts **ON** (passive only). Leave it that way until you intentionally arm.
3. **Nearby** → turn on continuous scan → walk the area; devices appear live.
4. **Engage** → tap **Scan My Network** (phone must be on the target Wi‑Fi).
5. **Tracks** → tap **Fuse** to merge BLE + Glass hosts into scored tracks.
6. Nothing “active” runs until you issue a consent token, clear the kill switch, and arm under **Command → Consent / Arm**.

---

## 4. Tab reference

### 4.1 Engage — Glass Fabric

| Control | What it does |
|---------|----------------|
| Query field | CIDR, private IP, or phrases like `scan my network` / `scan ble` |
| Pipeline picker | Auto / Glass Fabric / BLE |
| **Scan My Network** | Auto-detects LAN CIDR and runs Glass Fabric |
| **Nearby Bluetooth** | Hands off to BLE pipeline / Nearby tab |
| Lattice results | Hosts, services, fingerprints; per-host deep scan / IoT vulns / MQTT |
| **Persist** | Encrypt report into Vault (needs passphrase) |
| **Clear** | Wipe ephemeral session state |
| Export | SENTINEL JSON (`finch.sentinel.glass.v1`) from the lattice |

**Typical Glass inputs**

| Input | Example |
|-------|---------|
| Whole subnet | `192.168.1.0/24` |
| Single host | `192.168.1.50` |
| Natural language | `scan my network` |

**Per-host actions (after a sweep)**

- **Deep scan** — deeper port / service probes on one IP or all
- **IoT vulns** — fingerprint + CVE-style enrichment against bundled rules
- **MQTT** — listen on broker IP/port for a short window (default sheet; credentials in Settings)
- **Export** — share SENTINEL JSON off-device

Use only on LANs in scope. Local Network permission must be granted.

---

### 4.2 Nearby — BLE radar

| Control | What it does |
|---------|----------------|
| Continuous scan | Keep CoreBluetooth advertising scan running while you move |
| Device list | RSSI, estimated distance, friendly identity, tags |
| Tap device | Detail: connect, GATT map, **characteristic read** (read-only) |
| Long-press / context | Copy device, CVEs, distance, ID |
| Clear | Empty the in-memory radar list |

BLE data also feeds **Tracks** fusion automatically when device counts change.

**Honest limits:** scan + connect + read = yes. Characteristic **write**, clone, or MITM = not implemented on stock iOS.

---

### 4.3 Tracks — RF fusion

Fuses BLE advertisers, Glass hosts, mesh peer summaries, and Research Mode synthetics into `RFTrack` rows.

| Field | Meaning |
|-------|---------|
| Name / class | e.g. phone, AirTag, Flipper, drone, IoT |
| Primary source | `ble`, `wifiHost`, `synthetic`, `meshPeer`, … |
| Threat score | 1–10 with band + reasons |
| Distance | Approx. from RSSI when available |

Toolbar: **Fuse** (recompute) · **Clear** (drop fused tracks).

Open a row for detail (sources, threat reasons, drone meta when present).

**Threat hints (examples)**

| Signal | Score pressure |
|--------|----------------|
| Flipper / HackRF-class identity | High |
| Drone / controller class | Elevated |
| Very strong RSSI (close) | +1 |
| Playbook / anomaly history | Additional reasons |

---

### 4.4 Drone

| Action | Behavior |
|--------|----------|
| Passive list | Tracks classified as drone / controller from fusion |
| **Observe** | MAVLink observe path (Rx / audit — no Tx on stock iOS) |
| **Active…** menu | Consent-gated stubs: MITM, inject, fuzz, GPS spoof, RF deny, MAVLink command, etc. |
| **Refresh** | Re-pull detections from current fused tracks |

**Hard ceiling (on-device):** detect · classify · log = yes. Transmit / spoof / jam = **external authorized kit only**. The app arms, consents, and audits; it does not radiate those payloads itself.

Lab practice without real drones: **Command → Research Mode → Inject Drone**.

---

### 4.5 Command — hub

| Section | Contents |
|---------|----------|
| Situational | Live Map · AR Overlay · Consent / Arm · Forensic chain |
| Platform | Vault · Settings |
| Mesh | Advertise/browse Multipeer peers · Broadcast track summaries |
| Research Mode | Synthetic Flipper/Drone inject for lab demos |
| Playbooks | Bundled JSON rules; **Re-evaluate** against current tracks |

---

## 5. Consent, arm, and kill switch

Path: **Command → Consent / Arm**

Default state: **kill switch engaged** → all Tx paths blocked.

### Arm sequence (lab / authorized)

1. Under **Issue local lab token**: set Subject, validity (1–72 h), optional synthetic waiver.
2. Tap **Issue + load token (* scope)**.
3. Turn **Engage kill switch** **OFF**.
4. Tap **Arm system**.
5. Status should read like: `ARMED · consent <subject>`.

If arm fails, read **Last denial** (expired token, kill switch still on, bad signature, etc.).

### Disarm / abort

- Turn kill switch **ON** at any time → transmissions locked again.
- **Clear token** → back to passive-only even if previously armed.

Active menu items on Drone still record forensic denials/audits when gates fail — that is intentional.

---

## 6. Forensic chain

**Command → Forensic chain**

- Append-only events (consent changes, fusion highlights, playbook fires, active requests).
- Each event hashes into a chain tip (`finch.forensic.v1`).
- **Export** → share JSON off-device.
- **Reset** → wipe the in-memory chain (irreversible for that session’s log).

Use Export before wiping if you need an engagement record.

---

## 7. Vault & Settings

### Vault

- Ephemeral by default; **Persist** on Engage encrypts with AES-256-GCM when a passphrase is set.
- Set/rotate passphrase under **Command → Settings** or Vault.
- Key material is wiped when the app backgrounds (ephemeral session hygiene).
- Face ID can unlock Vault flows when configured.

### Settings highlights

| Setting | Effect |
|---------|--------|
| Continuous BLE by default | Nearby starts scanning on appear |
| Research Mode | Enables synthetic sensor / inject path |
| MQTT username/password | Defaults for listen sheets |
| Fingerprint reload | Reload bundled IoT fingerprint rules |
| About | Version string + schema ids |

---

## 8. Research Mode & playbooks

**Research Mode** (Command or Settings): lab-only synthetics.

- **Inject Flipper** / **Inject Drone** → appear in Tracks / Drone without real RF.
- Mark engagements clearly; forensic export notes `research=ON`.

**Bundled playbooks** (`default_playbooks.json`):

| ID | Trigger | Action idea |
|----|---------|-------------|
| `flipper-watch` | class flipper, threat ≥ 5 | forensic log + UI elevate |
| `drone-alert` | class drone, threat ≥ 4 | forensic log + drone hint |
| `hackrf-watch` | class hackrf, threat ≥ 6 | critical forensic path |
| `critical-any` | any track threat ≥ 8 | critical forensic log |

Tap **Re-evaluate** after fusion updates.

---

## 9. Map, AR, mesh

| Feature | How |
|---------|-----|
| Live Map | Command → Live Map — centers on phone location; proximity context for BLE |
| AR Overlay | Command → AR Overlay — camera reticles for fused tracks (ARKit devices) |
| Mesh | Toggle advertise+browse; **Broadcast tracks** shares summaries to nearby Finch peers (`_finch-mesh._tcp`) |

Mesh shares **summaries**, not full vault contents. Treat peer phones as part of the same authorized operator set.

---

## 10. Capability matrix (stock iPhone)

| Feature | Works? |
|---------|--------|
| BLE scan / GATT read | Yes |
| LAN IoT / MQTT listen | Yes |
| Track fusion + threat score | Yes |
| AR reticles | Yes (ARKit) |
| Forensic SHA-256 export | Yes |
| Consent + kill switch | Yes |
| Mesh track summaries | Yes |
| Research Mode inject | Yes |
| SDR capture / replay | Needs external SDR |
| BLE write / MITM / clone | Not implemented |
| MAVLink command / GPS spoof / jam | Consent + external kit — app audits only |

---

## 11. Suggested engagement flows

### A. Home / lab LAN check (passive)

1. Join in-scope Wi‑Fi.
2. Nearby: continuous scan ON.
3. Engage → **Scan My Network** → review Lattice.
4. Deep-scan interesting hosts; optional MQTT listen on known brokers.
5. Tracks → Fuse → note high scores.
6. Forensic → Export if you need a record.
7. Clear ephemeral when done.

### B. Walk-through BLE survey

1. Nearby continuous scan.
2. Walk floors; note Flipper / tracker / unknown strong RSSI.
3. Fuse Tracks; open details for copy/export.
4. Optional: Live Map while walking.

### C. Drone situational awareness (passive)

1. BLE + Glass running.
2. Drone tab → Refresh.
3. Observe only unless you have written scope **and** external kit.
4. Or Research Mode inject for UI/procedure rehearsal.

### D. Armed lab (authorized active path rehearsal)

1. Consent → issue local token → kill switch OFF → Arm.
2. Drone → Active… on a synthetic or authorized target.
3. Confirm forensic shows request + result/denial.
4. Kill switch ON when finished.

---

## 12. Export formats

| Export | Schema / file | From |
|--------|---------------|------|
| SENTINEL Glass report | `finch.sentinel.glass.v1` JSON | Engage lattice Export |
| Forensic chain | `finch.forensic.v1` JSON | Command → Forensic → Export |
| Vault item | Encrypted blob | Engage Persist / Vault |

---

## 13. Troubleshooting

| Symptom | Fix |
|---------|-----|
| No BLE devices | Bluetooth permission; physical phone; Continuous ON; leave Simulator |
| Glass finds nothing | Local Network permission; on correct Wi‑Fi; try explicit `192.168.x.0/24` |
| Can’t arm | Kill switch still ON, no/expired token, or signature invalid |
| Active op denied | Expected without arm + valid token + kill switch OFF |
| AR blank | Camera permission; ARKit-capable device |
| Vault won’t open | Passphrase wrong / Keychain wiped after reinstall |
| App won’t launch after ~7 days | Free Apple ID provisioning expired — re-sign IPA / reinstall from Xcode |
| Mesh no peers | Both phones on same LAN, mesh toggle ON, Local Network allowed |

---

## 14. Legal / operator rules

- Authorized targets only (own property, written scope, or explicit owner consent).
- Passive-by-default; treat arming as a deliberate act.
- Do not use Active menus against third-party aircraft, vehicles, or networks.
- Research Mode is for labs and demos — label exports accordingly.
- This manual does not grant authority; your engagement paperwork does.

---

## 15. Quick command card

```
OPEN → allow BT + Local Network
NEARBY → Continuous ON
ENGAGE → Scan My Network
TRACKS → Fuse
DRONE → Refresh (Observe only unless armed)
COMMAND → Forensic Export when done
ARMED PATH (lab): Consent issue → kill OFF → Arm → Active…
ABORT: kill switch ON
```

Companion docs: `README.md` · `WINDOWS_TO_IPHONE.md` · `MAC_CLOUD_SETUP.md` · `BUILD_UNSIGNED_IPA.sh`
