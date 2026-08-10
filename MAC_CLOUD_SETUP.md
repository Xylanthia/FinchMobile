# Finch Mobile — MacinCloud (finish install)

**Easiest path (no tokens, no Drive):** on the cloud Mac Terminal, paste this:

```bash
cd ~/Documents
curl -L -o FinchMobile.zip "https://github.com/rockstars4nny-hub/FinchMobile/releases/download/v0.1.0-mac/FinchMobile-clean.zip"
unzip -o FinchMobile.zip
cd FinchMobile
open FinchMobile.xcodeproj
```

Or clone:

```bash
cd ~/Documents
git clone https://github.com/rockstars4nny-hub/FinchMobile.git
cd FinchMobile
open FinchMobile.xcodeproj
```

Repo / release: https://github.com/rockstars4nny-hub/FinchMobile/releases/tag/v0.1.0-mac

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

- Allow **Bluetooth** and **Local Network**.
- Open **BLE Radar** or **Engage → Scan My Network**.

## When done

Apple menu → **Log Out** (or disconnect) so MacinCloud stops billing time.

Optional: after install, make the GitHub repo private again if you prefer.
