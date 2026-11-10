# Android APK Releases

The `Android APK Release` GitHub Actions workflow (`.github/workflows/android-release.yml`) runs automatically when:
- Code is pushed to `main` (including merged pull requests)
- A version tag matching `v*` (e.g., `v1.0.0`) is pushed
- Triggered manually via **Actions → Android APK Release → Run workflow**

It runs the test suite, builds a release APK with an incremented build number, and publishes the APK (`ScanMaster-<tag>.apk`) to **GitHub Releases** with custom release notes and auto-generated commit notes.

---

## How to Publish a New Version Release

1. **Update the version in `pubspec.yaml`**:
   ```yaml
   version: 1.1.0+1
   ```
2. **Add release notes for that version**:
   Create `.github/release-notes/1.1.0.md` describing what changed in `1.1.0`.
3. **Commit and push to `main` (or push a `v1.1.0` tag)**:
   ```bash
   git add pubspec.yaml .github/release-notes/1.1.0.md
   git commit -m "chore(release): prepare ScanMaster 1.1.0"
   git push origin main
   ```
   - Pushing to `main` publishes tag `v<version>-build.<run_number>` (e.g., `v1.1.0-build.12`) and uses `.github/release-notes/1.1.0.md` on the first release of version `1.1.0`.
   - Alternatively, pushing an explicit tag (`git tag v1.1.0 && git push origin v1.1.0`) publishes under that exact tag `v1.1.0`.

---

## One-Time Android Signing Setup (Recommended)

To ensure every GitHub Release APK is signed with the same persistent upload key (so users can install updates over existing installations without uninstalling):

1. Generate an upload keystore on your machine and keep a safe backup:
   ```sh
   keytool -genkeypair -v -keystore scanmaster-upload-key.jks -keyalg RSA \
     -keysize 2048 -validity 10000 -alias scanmaster
   base64 -w 0 scanmaster-upload-key.jks
   ```
2. In your GitHub repository, open **Settings → Secrets and variables → Actions** and add these 4 repository secrets:
   - `ANDROID_KEYSTORE_BASE64`: output of `base64 -w 0 scanmaster-upload-key.jks`
   - `ANDROID_KEY_ALIAS`: `scanmaster`
   - `ANDROID_KEY_PASSWORD`: your key password
   - `ANDROID_STORE_PASSWORD`: your keystore password

> Note: If none of the 4 secrets are set yet, the workflow still succeeds by falling back to debug signing so you can test the release pipeline immediately.
