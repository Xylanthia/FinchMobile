# Deploy Finch Mobile from a Windows PC (Dell) to iPhone

Apple only lets you **compile** iOS apps on **macOS + Xcode**. Your Dell Inspiron cannot build this project by itself. You still keep the source on Windows; you only need a Mac (or cloud Mac) for the build/sign step.

## What you need

| Item | Why |
|------|-----|
| iPhone (physical) | BLE + local network scanning need real hardware |
| Apple ID | Free is enough for personal device installs (~7-day cert refresh) |
| macOS build machine | Xcode, or a cloud Mac, or GitHub Actions `macos` runner |
| USB-C/Lightning cable (optional) | Direct install from Xcode; wireless works after first pair |

Paid Apple Developer ($99/yr) is optional — required for TestFlight / long-lived distribution, not for “install on my own phone.”

---

## Option A — Easiest: rent a cloud Mac (recommended on Windows)

Services: [MacinCloud](https://www.macincloud.com/), [MacStadium](https://www.macstadium.com/), [AWS EC2 Mac](https://aws.amazon.com/ec2/instance-types/mac/), etc.

1. On your Dell, zip or push this folder to GitHub:
   ```powershell
   cd C:\path\to\FinchMobile
   git init
   git add .
   git commit -m "Finch Mobile Glass"
   # create a GitHub repo, then:
   git remote add origin https://github.com/YOU/FinchMobile.git
   git push -u origin main
   ```
2. On the cloud Mac: install Xcode from the App Store, sign in with your Apple ID.
3. `git clone` your repo → open `FinchMobile.xcodeproj`.
4. In Xcode: **Signing & Capabilities** → Team = your Personal Team / Developer account.
5. Plug in the iPhone (or use network debugging) → select your phone as the run destination → **Run** (▶).
6. On the iPhone: **Settings → General → VPN & Device Management** → trust your developer certificate.

After the first install, you can reconnect later from the same Mac session to rebuild when the free provisioning expires (~7 days).

---

## Option B — Borrow / use any Mac once

Same as Option A steps 3–6. Copy the `FinchMobile` folder via USB drive, OneDrive, or GitHub. One afternoon on a friend’s Mac Mini/MacBook is enough to get it on your phone.

---

## Option C — GitHub Actions (build in the cloud from Windows)

This repo includes `.github/workflows/ios-build.yml`.

1. Push `FinchMobile` to a GitHub repo (from your Dell).
2. You still must **code-sign**. For CI signing you need:
   - An Apple Developer account
   - A Distribution/Development certificate + provisioning profile exported as secrets  
   (Free Personal Team signing is painful in CI; use a real Mac for free-team installs.)
3. For most Windows + free Apple ID users, **Option A or B is simpler** than wiring CI secrets.

The workflow at least verifies the project compiles on `macos-14` when signing is configured.

---

## Option D — What does *not* work

- Building with Visual Studio / Android Studio / WSL alone  
- Sideloading an unsigned `.ipa` without any Mac/signing step  
- App Store install (this is a private operator tool, not a store product)  
- Full BLE/LAN features in the iOS Simulator  

---

## After it’s on your iPhone

1. Open **Finch** → allow **Bluetooth** and **Local Network**.
2. **BLE Radar** tab → Continuous Scan on (walk/drive; list updates live).
3. **Engage** → `Scan My Network` or enter `192.168.x.0/24` for Glass Fabric.
4. Set a **Vault passphrase** in Settings before Persist.

Windows Finch (desktop Glass) and Finch Mobile are separate: the phone app does not need your Dell running. Both can sit on the same Wi‑Fi LAN for authorized assessments.

---

## Free Apple ID gotchas

- App may stop launching after ~7 days until you re-sign from Xcode.
- Some capabilities are limited vs paid team; this project uses only standard Bluetooth / local network / Face ID — fine for Personal Team.
- Always use a **physical iPhone**, not Simulator, for Glass + BLE.
