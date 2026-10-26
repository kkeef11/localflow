# Releasing LocalFlow

How a maintainer produces a signed, notarized `LocalFlow-<version>.zip` on GitHub Releases.
The pipeline is `.github/workflows/release.yml`, which runs `scripts/release.sh`. You can
run the same script locally.

> **Status:** the signed and notarized path has not been run end to end yet, because it
> needs Apple Developer Program credentials. Only the unsigned path (`--unsigned`) has
> run. It covers archiving, the bundle ID / version / entitlement checks, and packaging,
> but not the Developer ID export (`ExportOptions.plist`) or the signed-only checks
> (hardened runtime, team, `get-task-allow`). Do the first release as a dry run: push a
> `v0.1.0-rc.1` tag, then review the draft release before publishing.

## 1. One-time Apple setup

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

If any secret is missing, the workflow fails at the "Check signing secrets" step and lists
the missing names. It never produces an unsigned "release".

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
4. Archives a Release build with the hardened runtime and a secure timestamp.
5. Exports it with Developer ID signing.
6. Checks the bundle ID, version, entitlements and signature.
7. Notarizes the app with `notarytool`, then staples the ticket.
8. Checks the result with `stapler validate` and `spctl`.
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
