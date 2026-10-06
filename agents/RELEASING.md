# Releasing Jolt

Jolt is MIT licensed, ad-hoc signed, and not Apple-notarized. Its public identity is
`co.simonsc.jolt`. The website and signed Sparkle feed are hosted at
`https://smnsc.github.io/Jolt/`; immutable downloads live in GitHub Releases.

## One-time setup

1. Make `smnsc/Jolt` public after reviewing the repository and its history.
2. In repository Settings → Pages, choose **GitHub Actions** as the source.
3. Create a public `smnsc/homebrew-tap` repository with a `Casks/` directory.
4. Back up the Sparkle signing key from Keychain to secure offline storage. The
   account is `co.simonsc.jolt`. Never commit or paste the private key into a chat.
   Only `SUPublicEDKey` in `Resources/Info.plist` belongs in source control.

Sparkle's tools are available after resolving the package at
`build/SwiftPM/artifacts/sparkle/Sparkle/bin/`. `generate_keys --account co.simonsc.jolt`
creates the key if missing; `-p` displays its public key. Do not generate a new key
for an already released app. Without Developer ID, losing the update key requires
users to manually install a new build. Export/import options are documented by
`generate_keys --help`; keep any backup outside this repository.

## Prepare a release on your Mac

1. Run `swift test` (see DEVELOPMENT.md for the Xcode/cache fallback).
2. Build with `MARKETING_VERSION=0.1.0 scripts/build-app.sh`, substituting the new
   release version. The build number increments locally; if using another Mac,
   set `BUILD_NUMBER` greater than the highest published number. Record the exact
   **Jolt build N** printed by the script.
3. Test the packaged app: launch, connection, search, preferences, login item,
   donation link, update settings, and Check for Updates. Test macOS 14 and Intel
   on suitable hardware before claiming those configurations verified.
4. Write release notes, then run:

   ```sh
   scripts/prepare-release.py agents/releases/0.1.0.md
   ```

   This verifies the app and public key, prepares a drag-to-Applications DMG and
   ZIP, signs the update archive and feed through Keychain, verifies the feed,
   and writes SHA256 checksums plus a Homebrew cask. Outputs are in ignored
   `build/releases/v0.1.0/`. Existing release folders are never overwritten.

The app's update configuration is production-only by default. For local updater
QA, build with `UPDATE_FEED_URL` pointing at a controlled test feed. The release
script rejects test-feed builds. Use two actual builds for install/relaunch QA,
and verify a tampered archive is rejected. Keep the normal public feed unchanged
until the matching release downloads exist. Never modify a signed feed by hand.

## Publish in this order

1. Commit and push the reviewed source; create a matching `v0.1.0` Git tag.
2. Create a GitHub Release for that tag. Upload `Jolt-0.1.0.dmg`,
   `Jolt-0.1.0.zip`, and `SHA256SUMS`, and use `RELEASE_NOTES.md` as its notes.
   Download the uploaded ZIP and verify its checksum before continuing.
3. Copy the generated `appcast.xml` into `website/appcast.xml`, commit and push.
   The Pages workflow deploys it with the site. Verify the live feed and perform
   an update from the previous installed version. Retain previous release assets.
4. Copy generated `jolt.rb` into `smnsc/homebrew-tap/Casks/jolt.rb`, then run
   `brew style` and a fresh `brew install --cask smnsc/tap/jolt` before advertising
   Homebrew installation. The cask declares `auto_updates true`; Homebrew normally
   skips these during upgrades unless `--greedy` is used.

No private signing key is needed in GitHub Actions: build/sign on the maintainer's
Mac, upload the finished artifacts, and let Pages serve the signed feed unchanged.
The CI workflow runs tests and builds but does not publish or sign update archives.

## User-visible constraints

- Initial browser downloads require macOS's **Open Anyway** approval. Never tell
  users to disable Gatekeeper globally or remove quarantine as the default path.
- Ad-hoc builds have hash-bound identities. Keychain may deny a newer build access
  to an older build's credentials; users may need to reconnect Jira. Do not weaken
  the code requirement to the bundle identifier alone to bypass this protection.
- The identity change from `com.local.Jolt` starts a new sandbox/preferences domain
  and Keychain service. Existing development installs need reconnecting and their
  settings reapplied. Turn off the old build's login item before replacing it, then
  enable launch at login in the new build if wanted.
- Updater signatures prove the update came from the holder of Jolt's update key;
  they do not provide Apple notarization. Validate install/relaunch on a downloaded
  build before the first public release.
