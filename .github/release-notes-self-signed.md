## Installing

This build is signed but **not notarized by Apple**, so macOS blocks the first launch:

1. Unzip `LocalFlow-*.zip` and drag **LocalFlow.app** into **Applications**.
2. Open LocalFlow. macOS says it can't verify the app — click **Done** (not "Move to Trash").
3. Open **System Settings → Privacy & Security**, scroll down, and click **Open Anyway** next to LocalFlow. Confirm with your password.

You only do this once per version. When upgrading, macOS keeps your Microphone, Accessibility and Input Monitoring permissions because every release is signed with the same certificate.

Verify the download: `shasum -a 256 -c LocalFlow-*.zip.sha256`
