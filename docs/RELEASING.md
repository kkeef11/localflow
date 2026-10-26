# Releasing LocalFlow

How a maintainer produces a signed `LocalFlow-<version>.zip` on GitHub Releases. The
pipeline is `.github/workflows/release.yml`, which runs `scripts/release.sh`. You can run
the same script locally.

## Two signing routes

The workflow picks the route from the repository secrets that exist.

| | Self-signed (free) | Developer ID (US$99/year) |
|---|---|---|
| Secrets | `SELF_SIGNED_P12_BASE64`, `SELF_SIGNED_P12_PASSWORD` | the six in section 2 |
| First launch | Blocked by Gatekeeper; users click **Open Anyway** in System Settings once per version | Opens normally after the usual "downloaded from the internet" prompt |
| Permissions kept across upgrades | Yes (same certificate) | Yes (same team) |
| Who it suits | You and people you can walk through install | Anyone |

If both sets of secrets exist, Developer ID wins. Switching routes changes the app's
signature, so every user grants Microphone, Accessibility and Input Monitoring once more.

## Self-signed releases (free)

**Status:** verified locally. Two builds signed with the same certificate had different
code but an identical designated requirement (`identifier "com.kkeefer.LocalFlow" and
certificate leaf = H"…"`), which is what macOS checks when deciding whether earlier
permission grants still apply. Not yet verified: an actual upgrade on a Mac with
permissions granted, and a run of the workflow on GitHub.

1. **Create the certificate once.** It is written outside the repository:
   ```bash
   scripts/create-signing-cert.sh            # -> ~/LocalFlow-signing/
   ```
   This runs only `openssl`. It doesn't touch your keychain or system settings. The
   certificate is valid for 10 years.
2. **Back it up.** Store `LocalFlow-Self-Signed.p12` and `p12-password.txt` in a password
   manager. **Never generate a second one.** A release signed with a different
   certificate resets every user's permissions. The script refuses to overwrite an
   existing certificate.
3. **Add the two secrets** (the script prints these commands with your paths):
   ```bash
   gh secret set SELF_SIGNED_P12_BASE64 < <(base64 -i ~/LocalFlow-signing/LocalFlow-Self-Signed.p12)
   gh secret set SELF_SIGNED_P12_PASSWORD < ~/LocalFlow-signing/p12-password.txt
   ```
4. **Tag a release** as in section 4. The draft release includes install instructions for
   users (`.github/release-notes-self-signed.md`), above the generated changelog.

To build a self-signed release on your own Mac, import the `.p12` into a keychain and run
`scripts/release.sh 0.2.0 --self-signed`. Pass `SIGNING_KEYCHAIN=<path>` if it isn't in
your login keychain. The script adds that keychain to your search list while it runs and
restores the list afterwards.

The rest of this document covers the Developer ID route. Sections 3–6 (versioning,
making a release, verifying, troubleshooting) apply to both.

> **Status:** the signed and notarized path has not been run end to end yet, because it
> needs Apple Developer Program credentials. Only the unsigned path (`--unsigned`) has
> run. It covers archiving, the bundle ID / version / entitlement checks, and packaging,
> but not the Developer ID export (`ExportOptions.plist`) or the signed-only checks
> (hardened runtime, team, `get-task-allow`). Do the first release as a dry run: push a
> `v0.1.0-rc.1` tag, then review the draft release before publishing.

## 1. One-time Apple setup (Developer ID route only)

You need a paid **Apple Developer Program** membership (US$99/year). A free Apple ID can
sign builds for your own Mac, but it can't issue Developer ID certificates or notarize.

### Developer ID Application certificate

1. Xcode → Settings → Accounts → select your team → **Manage Certificates…** → **+** →
   **Developer ID Application**. Only the team's *Account Holder* can create one. You can
   also create it at developer.apple.com → Certificates.
2. Open Keychain Access → *login* → *My Certificates*. Right-click
   **Developer ID Application: Your Name (TEAMID)** → **Export…**. Save it as
   `DeveloperID.p12` with a strong password. The export must include the private key.
3. Your **Team ID** is the 10 characters in parentheses in that name. It's also shown at
   developer.apple.com → Membership.

Keep the `.p12` file out of the repository. `.gitignore` blocks `*.p12`, `*.p8` and
`*.cer` as a safety net.

### Notarization API key (App Store Connect)

1. App Store Connect → **Users and Access** → **Integrations** → **App Store Connect API**
   → **Team Keys** → **+**. Give it the **Developer** role.
2. Download `AuthKey_<KEYID>.p8`. It can only be downloaded once. Note the **Key ID** and
   the **Issuer ID**, which is shown above the key list.

## 2. GitHub repository secrets

The values below are what `release.yml` expects. You can set them from a terminal in the
repository:

```bash
gh secret set DEVELOPER_ID_P12_BASE64   < <(base64 -i DeveloperID.p12)
gh secret set DEVELOPER_ID_P12_PASSWORD   # prompts for the .p12 export password
gh secret set DEVELOPER_ID_TEAM           # e.g. ABCDE12345
gh secret set NOTARY_API_KEY_P8_BASE64  < <(base64 -i AuthKey_XXXXXXXXXX.p8)
gh secret set NOTARY_API_KEY_ID           # e.g. XXXXXXXXXX
gh secret set NOTARY_API_ISSUER_ID        # a UUID
```

| Secret | What it is |
|---|---|
| `DEVELOPER_ID_P12_BASE64` | Base64 of the exported Developer ID Application `.p12` (certificate + private key) |
| `DEVELOPER_ID_P12_PASSWORD` | The `.p12` export password |
| `DEVELOPER_ID_TEAM` | 10-character Apple Team ID |
| `NOTARY_API_KEY_P8_BASE64` | Base64 of the App Store Connect API key `.p8` |
| `NOTARY_API_KEY_ID` | That key's Key ID |
| `NOTARY_API_ISSUER_ID` | App Store Connect Issuer ID |

The "Choose signing mode" step uses Developer ID when all six are set and the self-signed
certificate otherwise. If only some of the six are set, it fails and lists the missing
names rather than silently falling back. With no signing secrets at all, it fails. It
never produces an unsigned "release".

## 3. Versioning

- Tags look like `vMAJOR.MINOR.PATCH`, optionally with a pre-release suffix such as
  `v0.2.0-beta.1`. Suffixed tags become GitHub pre-releases.
- `MARKETING_VERSION` in `project.yml` must equal the tag without the `v` and the suffix.
  The workflow refuses a mismatch, so the source tree always states its own version.
- The build number (`CFBundleVersion`) is the commit count on the tagged commit, so it
  always increases along `main`.
- The tag must point at a commit on `main`.
- **Never change** the bundle identifier (`com.kkeefer.LocalFlow`) or the signing Team ID.
  macOS ties a user's permission grants to both. Changing either makes every user grant
  Microphone, Accessibility and Input Monitoring again.

## 4. Making a release

```bash
# 1. Bump the version (e.g. 0.1.0 -> 0.2.0) and commit to main
sed -i '' 's/MARKETING_VERSION: "0.1.0"/MARKETING_VERSION: "0.2.0"/' project.yml
git commit -am "chore: release 0.2.0" && git push origin main

# 2. Tag and push — this starts the Release workflow
git tag v0.2.0 && git push origin v0.2.0

# 3. Watch it
gh run watch "$(gh run list --workflow=release.yml --limit 1 --json databaseId -q '.[0].databaseId')"
```

The workflow does the following:

1. Validates the tag.
2. Runs the unit tests.
3. Imports the certificate into a throwaway keychain.
4. Archives a Release build with the hardened runtime.
5. Signs it: Developer ID export (with a secure timestamp), or a re-sign with the
   self-signed certificate.
6. Checks the bundle ID, version, entitlements and signature. For self-signed builds it
   also checks that the designated requirement pins the certificate.
7. Developer ID only: notarizes the app with `notarytool` and staples the ticket.
8. Developer ID only: checks the result with `stapler validate` and `spctl`.
9. Zips the app with `ditto` and writes a `.sha256` file.
10. Creates a **draft** release with both files attached.

Review the draft on GitHub, then click **Publish release**.

### Dry run locally

```bash
scripts/release.sh 0.2.0 --unsigned        # no credentials: archive + packaging only (no Developer ID export)
```

To produce a signed, notarized build from your own Mac, first store notarization
credentials in your keychain once:

```bash
xcrun notarytool store-credentials localflow-notary \
  --key AuthKey_XXXXXXXXXX.p8 --key-id XXXXXXXXXX --issuer <issuer-uuid>
```

Then run:

```bash
DEVELOPER_ID_TEAM=ABCDE12345 NOTARY_KEYCHAIN_PROFILE=localflow-notary scripts/release.sh 0.2.0
```

Output goes to `dist/`, which is git-ignored.

## 5. Verifying a downloaded release

Run these on a Mac that did **not** build it, ideally one without Xcode:

```bash
cd ~/Downloads
shasum -a 256 -c LocalFlow-0.2.0.zip.sha256          # -> LocalFlow-0.2.0.zip: OK
ditto -x -k LocalFlow-0.2.0.zip .
codesign -dv --verbose=4 LocalFlow.app                # Authority=Developer ID Application: …, flags=…(runtime)
codesign --verify --deep --strict --verbose=2 LocalFlow.app
spctl --assess --type execute --verbose=4 LocalFlow.app   # accepted, source=Notarized Developer ID
xcrun stapler validate LocalFlow.app                  # The validate action worked!
```

For a self-signed release, the expected results differ:

```bash
codesign -dv --verbose=4 LocalFlow.app       # Authority=LocalFlow Self-Signed, flags=…(runtime)
codesign -d -r- LocalFlow.app                # … certificate leaf = H"<same hash every release>"
spctl --assess --type execute LocalFlow.app  # rejected (expected: not notarized)
```

## 6. Troubleshooting release failures

| Symptom | Fix |
|---|---|
| `Missing repository secrets: …` | Add the listed secrets (section 2). |
| `project.yml MARKETING_VERSION is …` | Bump `project.yml`, commit, delete the tag (`git push --delete origin vX.Y.Z; git tag -d vX.Y.Z`), then tag again. |
| `no valid "Developer ID Application" identity` | The `.p12` has no private key, or it's an *Apple Development* / *Developer ID Installer* certificate. Export the right one again. |
| `errSecInternalComponent` while signing | The keychain is locked or its partition list wasn't set. Re-run the job; locally, unlock your login keychain. |
| Notarization `Invalid` | `release.sh` prints the notary log. Common causes: a missing hardened runtime, a `get-task-allow` entitlement (a Debug build), or an unsigned nested binary. |
| Notarization hangs or times out | Apple's service is slow sometimes. `notarytool` waits up to 30 minutes, so re-run the job. Check status with `xcrun notarytool history`. |
| `spctl … rejected` after stapling | The certificate was revoked or expired, or the ticket didn't staple. Check `codesign -dv` and `stapler validate`. |
| Package resolution errors | `Config/Package.resolved` is stale. Run `scripts/build.sh lock`, then review and commit the diff. |

## 7. Toolchain pins

`.github/actions/setup-tools/action.yml` pins the Xcode and XcodeGen versions. The XcodeGen
pin includes the archive's SHA-256, which you can read from the GitHub API:

```bash
gh api repos/yonaskolb/XcodeGen/releases/tags/2.46.0 --jq '.assets[] | .name + " " + .digest'
```

When you bump either one, run CI on a branch first.

## Why there's no auto-updater

Sparkle would need an appcast feed, EdDSA update-signing keys and their custody, and a
second signing step for every release. That isn't worth it at the current release
cadence. Users upgrade by downloading the new zip and replacing the app. Settings and
models survive the upgrade (see README → Upgrading). Revisit this if releases become
frequent.
