# Finch Mobile — MacinCloud (finish install)

**Use the latest zip (last-session updates):**  
`C:\Users\nixon\Downloads\FinchMobile-latest.zip`  
Upload that to the cloud Mac (Drive / portal), then:

```bash
cd ~/Documents
unzip -o ~/Downloads/FinchMobile-latest.zip -d FinchMobile
# if unzip landed files in Documents already:
#   cd ~/Documents && unzip -o ~/Downloads/FinchMobile-latest.zip
cd ~/Documents/FinchMobile
open FinchMobile.xcodeproj
```

Do **not** use the old GitHub `v0.1.0-mac` zip — it is missing plain-language BLE names + CVE mapping.

Or clone (only if `main` has been pushed with those updates):

```bash
cd ~/Documents
git clone https://github.com/rockstars4nny-hub/FinchMobile.git
cd FinchMobile
open FinchMobile.xcodeproj
```

## In Xcode (after project opens)

1. Click the blue **FinchMobile** project in the left sidebar.
2. Select the **FinchMobile** target → **Signing & Capabilities**.
3. Check **Automatically manage signing**.
4. **Team** → **Add Account…** → sign in with your **Apple ID** → pick **Personal Team**.
5. At the top, set the run destination to **Any iOS Device** (or your iPhone if paired).
6. **Product → Archive** (for Sideloadly `.ipa`) **or** **Product → Run** if the phone is connected/wireless to this Mac.

### Sideloadly path (iPhone plugged into your Dell)

1. Xcode → **Product → Archive** → **Distribute App** → **Development** → export `.ipa`.
2. Download the `.ipa` from the cloud Mac (Drive / email / portal download).
3. On Windows: [Sideloadly](https://sideloadly.io/) → iPhone + Apple ID → install `.ipa`.
4. iPhone: **Settings → General → VPN & Device Management** → Trust.

## After install on iPhone

- Allow **Bluetooth** and **Local Network**. Enable **Developer Mode** if asked.
- Title should show **FINCH · GLASS 1.1**.
- **Engage → Scan My Network** → **IoT Vulns** for full module-6 style run.
- **BLE Radar** → tap a device → **Connect + Map GATT** (read-only).

## When done

Apple menu → **Log Out** (or disconnect) so MacinCloud stops billing time.

Optional: after install, make the GitHub repo private again if you prefer.

## Tonight’s zip (Windows)

Fresh source is already at:

`C:\Users\nixon\Downloads\FinchMobile.zip`

Upload that to the cloud Mac (Drive) or use `BUILD_UNSIGNED_IPA.sh` after unzip.
