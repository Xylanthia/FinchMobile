# Finch Mobile — MacinCloud (finish install)

Repo: **https://github.com/rockstars4nny-hub/FinchMobile** (private)

You cannot paste a whole folder into the cloud Mac. Use Terminal + git (below).

## On the cloud Mac Terminal — copy/paste this entire block

```bash
cd ~/Documents
git clone https://github.com/rockstars4nny-hub/FinchMobile.git
cd FinchMobile
open FinchMobile.xcodeproj
```

If git asks you to log in: use your **GitHub** username + a **Personal Access Token** (or sign in via the browser prompt). Same account that owns `rockstars4nny-hub`.

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
