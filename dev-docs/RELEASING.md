# Releasing Jolt

Jolt is MIT licensed, ad-hoc signed, and not Apple-notarized. Its public identity is
`co.simonsc.jolt`. The website and signed Sparkle feed are hosted at
`https://smnsc.github.io/Jolt/`; immutable downloads live in GitHub Releases.

## One-time setup

1. Make `smnsc/Jolt` public after reviewing the repository and its history.
2. In repository Settings → Pages, choose **GitHub Actions** as the source.
3. Optionally create a public `smnsc/homebrew-tap` repository with a `Casks/` directory.
4. Back up the Sparkle signing key from Keychain to secure offline storage. The
   account is `co.simonsc.jolt`. Never commit or paste the private key into a chat.
   Only `SUPublicEDKey` in `Resources/Info.plist` belongs in source control.

Sparkle's tools are available after resolving the package at
`build/SwiftPM/artifacts/sparkle/Sparkle/bin/`. `generate_keys --account co.simonsc.jolt`
creates the key if missing; `-p` displays its public key. Do not generate a new key
for an already released app. Without Developer ID, losing the update key requires
users to manually install a new build. Export/import options are documented by
`generate_keys --help`; keep any backup outside this repository.

5. In **Settings → Environments → release**, add the environment secret
   `SPARKLE_PRIVATE_KEY`. Its value must be the exact text exported by Sparkle's
   `generate_keys --account co.simonsc.jolt -x /secure/path/key` (not the public
   key or a second base64 encoding). The workflow checks it against the app's
   public key. Restrict this environment to `main`; required reviewers are optional.
6. Push `.github/workflows/release.yml` and `pages.yml` to `main`. In **Settings →
   Actions → General**, allow Actions to run. The workflows request the required
   token permissions; no personal access token secret is needed.
7. Install GitHub CLI (`brew install gh`) and authenticate once with `gh auth login`.

## Automated release (recommended)

1. Add reviewed notes to `dev-docs/releases/VERSION.md`. Update the default version
   in `Resources/Info.plist` for subsequent development builds.
2. Commit and push to `main`, then run from a clean checkout matching remote main:

   ```sh
   scripts/release.sh 0.1.0
   ```

   Substitute a new `MAJOR.MINOR.PATCH` version greater than the latest release.
   This publishes a public release. Alternatively, use **Actions → Release → Run
   workflow**, select `main`, and enter the version.
3. Follow **Actions → Release**, approve the environment if you configured required
   reviewers, then follow **Deploy website**. Terminal status commands:

   ```sh
   gh run list --workflow release.yml
   gh run list --workflow pages.yml
   ```

The workflow tests and builds both architectures, uses a timestamp build number,
passes the secret through a temporary private-key file, and checks its public
key without Keychain prompts. It verifies the previous feed, packages and signs the update, uploads a draft,
downloads and checks the assets, then publishes the release and dispatches Pages.
The run summary records **Jolt build N**. An existing tag or release is never
replaced. The private-key file is removed even on failure. Signing tools have ten-minute
timeouts, the packaging step has a fifteen-minute limit, and the job has a thirty-minute limit. Release artifacts contain no private key.

Only the DMG and update ZIP are attached to public releases. Checksums and the
optional Homebrew cask stay in the recovery artifact. After verifying and publishing
the downloads, the workflow commits the signed feed unchanged to `docs/appcast.xml`
on `main`, then explicitly dispatches Pages. Repository rules must allow this bot
commit; if branch protection blocks it, commit the feed manually as described below.
Pages uses the committed feed to set both HTML download buttons to the matching DMG
automatically. Never edit the signed XML by hand. Keep previous app downloads.

When migrating from the old workflow, preserve the latest release's signed feed in
`docs/appcast.xml`, push these workflow changes, and deploy the website first. Then
remove only `appcast.xml`, `SHA256SUMS`, and `jolt.rb` from the old release attachments.
Do not remove the ZIP: existing Sparkle feeds reference it.

If publishing fails, inspect the draft and the saved Actions artifact before
retrying; a draft reserves its version. Delete a failed, **unpublished** draft/tag
only after checking that no public release used it. Never replace public assets.
If the release publishes but committing the feed fails, download the saved Actions
artifact, copy its `appcast.xml` unchanged into `docs/appcast.xml`, and commit/push it
to `main`. Do not rerun the release or rebuild its downloads. If the feed commit
succeeded but Pages failed, fix its settings and retry just deployment:

```sh
gh workflow run pages.yml --ref main
```

After both workflows succeed, download the DMG through the website, check its
checksum and first launch, and test an update from an older install. Hosted tests
cannot verify Jira login, Gatekeeper interaction, or updater install/relaunch.

## Prepare a release on your Mac (manual alternative)

1. Run `scripts/test.sh` (selects Xcode and uses local build caches).
2. Build with `MARKETING_VERSION=0.1.0 scripts/build-app.sh`, substituting the new
   release version (`MAJOR.MINOR.PATCH`, without leading zeros). Update the default
   in `Resources/Info.plist` for subsequent development builds. Settings shows
   `MAJOR.MINOR.PATCH+build.N`. The build number increments locally; if using another Mac,
   set `BUILD_NUMBER` greater than the highest published number. Record the exact
   **Jolt build N** printed by the script.
3. Test the packaged app: launch, connection, search, preferences, login item,
   donation link, update settings, and Check for Updates. Test macOS 14 and Intel
   on suitable hardware before claiming those configurations verified.
4. Write release notes, then run:

   ```sh
   scripts/prepare-release.py dev-docs/releases/0.1.0.md
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
   `Jolt-0.1.0.zip`, and use `RELEASE_NOTES.md` as its notes. Keep `SHA256SUMS` locally.
   Download the uploaded ZIP and verify its checksum before continuing.
3. Copy the generated signed `appcast.xml` into `docs/appcast.xml`, commit and push
   to `main`, then run `gh workflow run pages.yml --ref main`. Verify the live feed
   and perform an update from the previous installed version. Retain previous assets.
4. Copy generated `jolt.rb` into `smnsc/homebrew-tap/Casks/jolt.rb`, then run
   `brew style` and a fresh `brew install --cask smnsc/tap/jolt` before advertising
   Homebrew installation. The cask declares `auto_updates true`; Homebrew normally
   skips these during upgrades unless `--greedy` is used.

The separate Test workflow never receives the release secret; only the manually
triggered Release workflow signs and publishes.

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
