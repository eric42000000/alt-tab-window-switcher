# AltTab Window Switcher

A lightweight, native macOS app for switching between apps and their individual windows. Press **⌘Tab** to bring up the switcher, choose an app, then choose one of that app’s open windows.

AltTab Window Switcher is an independent app. It does not use or require the separate `AltTab` app (`com.lwouis.alt-tab-macos`); running both at once creates a keyboard-shortcut conflict.

## Features

- Shows recently used apps first.
- Shows a window chooser only for apps with multiple detected windows.
- Navigate the horizontal window strip with the arrow keys; the selected window scrolls into view.
- Uses window titles and metadata from the macOS Accessibility API.
- Can show window thumbnails, or privacy-friendly wireframe previews if Screen Recording access is not granted.
- Lives in the menu bar and can also open the switcher on demand.

## Install

1. Download the latest `AltTabWindowSwitcher-macOS-universal.zip` from the repository’s **Releases** page.
2. Unzip it and drag `AltTabWindowSwitcher.app` into **Applications**.
3. Open the app. In **System Settings → Privacy & Security → Accessibility**, enable **AltTab Window Switcher**, then quit and reopen it. This permission is required for the global shortcut and for raising the selected window.
4. The first time you open the switcher, macOS may ask for **Screen Recording** access. It is optional: allow it for real window thumbnails, or choose **Use Wireframes** to continue without it.

If there is no downloadable release yet, build the app from source using the steps below.

## Use

| Shortcut or action | Result |
| --- | --- |
| **⌘Tab** while the switcher is closed | Open the app switcher |
| **⌘Tab** while it is open | Select the next app |
| **⇧⌘Tab** while it is open | Select the previous app |
| **Return**, **Space**, or **W** on an app | Show its windows, if it has more than one |
| **Arrow keys** in the window chooser | Move through windows; the selected preview scrolls into view |
| **Return** or **Space** in the window chooser | Bring the selected window forward |
| **Escape** | Close the switcher without changing windows |
| Click an app | Open its window chooser, or activate it directly if it has only one detected window |
| Click a window | Bring that window forward immediately |

Use the **⌘⇥** menu-bar item to show the switcher manually, reopen the Accessibility prompt, open Screen Recording settings, or quit the app.

## Permissions and privacy

**Accessibility is required.** The app uses a Quartz keyboard event tap to receive ⌘Tab globally, and Accessibility window metadata/actions to list and raise windows. If you grant access while the app is open, quit and reopen it so macOS applies the permission.

**Screen Recording is optional.** It is used only to capture still window thumbnails while the switcher is visible. The app does not continuously record, capture in the background, or save captured images. If access is denied, choose **Use Wireframes**; app and window selection still work.

The app keeps a local list of recently activated app identifiers so it can sort apps by recency. It does not send this list, window titles, or screenshots to a server.

## Requirements

- macOS 13 or later
- Apple silicon or Intel Mac (the release workflow builds a universal app)
- Xcode Command Line Tools to build from source

## Build from source

```sh
xcode-select --install
git clone https://github.com/eric42000000/alt-tab-window-switcher.git
cd alt-tab-window-switcher
./build_app.sh
open AltTabWindowSwitcher.app
```

The local build is ad-hoc signed for development. To sign with a certificate installed in your login keychain, set `SIGNING_IDENTITY`:

```sh
SIGNING_IDENTITY="Apple Development: Your Name (TEAMID)" ./build_app.sh
```

To build a universal arm64/x86_64 app locally, run `BUILD_UNIVERSAL=1 ./build_app.sh`.

The project uses Swift Package Manager and has no third-party package dependencies. The bundle identifier is `com.ericmongeon.altTabWindowSwitcher`.

## Releases and signing

Pushing a version tag such as `v1.8` runs the GitHub Actions release workflow. It checks that the tag matches `CFBundleShortVersionString`, builds a universal arm64/x86_64 app, signs it, submits it to Apple for notarization, staples the ticket, and publishes a ZIP plus SHA-256 checksum.

Before enabling that workflow, configure these repository Actions secrets:

| Secret | Description |
| --- | --- |
| `APPLE_CERTIFICATE_P12_BASE64` | Base64-encoded **Developer ID Application** certificate exported as a `.p12` |
| `APPLE_CERTIFICATE_PASSWORD` | Password used when exporting that `.p12` |
| `APPLE_SIGNING_IDENTITY` | Full Developer ID Application identity, including team ID |
| `APPLE_ID` | Apple Account used for notarization |
| `APPLE_TEAM_ID` | Apple Developer team ID |
| `APPLE_APP_SPECIFIC_PASSWORD` | App-specific password for the Apple Account |

Keep signing credentials only in GitHub Actions secrets—never commit certificates, passwords, or private keys. Apple Developer ID signing and notarization are what make a downloaded release launch cleanly through macOS Gatekeeper. Local ad-hoc builds are for development, not public binary distribution.

Export the Developer ID Application certificate together with its private key from Keychain Access as a password-protected `.p12` file. On macOS, encode it for the GitHub secret with `base64 -i DeveloperID.p12 | pbcopy`. Find the identity string for `APPLE_SIGNING_IDENTITY` with `security find-identity -v -p codesigning`. Use an Apple app-specific password for notarization, not your normal account password.

See Apple’s [macOS notarization requirements](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution) for details.

To publish a release:

1. Add the secrets above under **Repository Settings → Secrets and variables → Actions**.
2. Update `CFBundleShortVersionString` and `CFBundleVersion` in `Info.plist`, then merge the release commit to `main`.
3. Create and push a tag matching the marketing version, for example `git tag v1.9 && git push origin v1.9`.
4. Wait for the **Release** workflow to finish; it creates the GitHub release and attaches the notarized app ZIP and checksum.

To check a downloaded archive’s checksum, place the ZIP and its `.sha256` file in the same directory and run:

```sh
shasum -a 256 -c AltTabWindowSwitcher-macOS-universal.zip.sha256
```

## Troubleshooting

- **⌘Tab does nothing:** Check that the app is enabled under **System Settings → Privacy & Security → Accessibility**, then quit and reopen it.
- **A different AltTab app is running:** Quit the other app from its menu-bar icon and reopen AltTab Window Switcher. Both apps try to own ⌘Tab.
- **Previews show wireframes:** Grant Screen Recording access in **System Settings → Privacy & Security → Screen Recording**, then reopen the switcher. You can also keep using wireframes; thumbnails are optional.
- **An app or window is missing:** Some apps expose incomplete window metadata to macOS Accessibility. Confirm that the window is visible and that Accessibility access remains enabled.

## License

See [LICENSE](LICENSE).
