# fish-skills

Distribution repo for standalone binaries of [vercel-labs/skills](https://github.com/vercel-labs/skills) — the CLI for the open agent skills ecosystem.

## Install

```bash
curl -fsSL https://raw.githubusercontent.com/pavanpaik/fish-skills/main/install.sh | bash
```

Or download a binary directly from [Releases](https://github.com/pavanpaik/fish-skills/releases).

| Platform      | Binary               |
| ------------- | -------------------- |
| macOS (Apple) | `skills-macos-arm64` |
| macOS (Intel) | `skills-macos-x64`   |
| Linux x64     | `skills-linux-x64`   |
| Windows x64   | `skills-win-x64.exe` |

---

## Releasing a New Version

### Prerequisites

| Tool | Install |
| ---- | ------- |
| Node.js ≥ 18 | [nodejs.org](https://nodejs.org) |
| pnpm | `npm install -g pnpm` |
| gh (GitHub CLI) | `brew install gh` then `gh auth login` |
| git | pre-installed on macOS |

### Run the release script

```bash
# Uses the upstream package.json version as the tag
./scripts/release.sh

# Pin a specific tag
./scripts/release.sh v1.5.0
```

The script will:
1. Clone `vercel-labs/skills`
2. `pnpm install` + `pnpm build`
3. Bundle with esbuild and patch for binary compatibility
4. Compile binaries for all four platforms via `@yao-pkg/pkg`
5. Code-sign the macOS binaries
6. Create a GitHub Release with the binaries attached

---

## macOS Code Signing

macOS will block unsigned binaries. The script handles signing automatically when run on macOS, but you need a signing identity first.

### Option A: Ad-hoc signing (free, no Apple account)

No setup needed — the script uses `codesign --sign -` by default. Users will need to clear the quarantine attribute after downloading:

```bash
xattr -d com.apple.quarantine ./skills-macos-arm64
```

### Option B: Developer ID signing (recommended for public releases)

Requires an **Apple Developer account** ($99/year at [developer.apple.com/programs](https://developer.apple.com/programs)).

#### Step 1 — Get a Developer ID certificate

**Via Xcode (easiest):**
1. Xcode → Settings → Accounts → add your Apple ID
2. Click **Manage Certificates** → **+** → **Developer ID Application**
3. Xcode installs it into your Keychain automatically

**Via web + CLI (no Xcode):**
```bash
# Generate a Certificate Signing Request
openssl req -new -newkey rsa:2048 -nodes \
  -keyout mykey.pem \
  -out myrequest.csr \
  -subj "/emailAddress=you@example.com/CN=Your Name/C=US"
```
Upload `myrequest.csr` at **developer.apple.com → Certificates → +**, choose **Developer ID Application**, download the `.cer`, then double-click to install.

#### Step 2 — Find your identity string

```bash
security find-identity -v -p codesigning
```

Output:
```
1) A1B2C3D4E5... "Developer ID Application: Your Name (ABCD1234EF)"
```

#### Step 3 — Release with your identity

```bash
CODESIGN_IDENTITY="Developer ID Application: Your Name (ABCD1234EF)" \
  ./scripts/release.sh
```

The script reads `CODESIGN_IDENTITY` and falls back to ad-hoc (`-`) if not set.

#### Step 4 — Notarization (optional but recommended)

After signing, submit to Apple so Gatekeeper fully trusts the binary:

```bash
zip skills-macos-arm64.zip dist-bin/skills-macos-arm64

xcrun notarytool submit skills-macos-arm64.zip \
  --apple-id "you@example.com" \
  --team-id "ABCD1234EF" \
  --password "@keychain:AC_PASSWORD" \
  --wait
```

> **Tip:** Store your App Store Connect password in Keychain once:
> ```bash
> xcrun notarytool store-credentials "AC_PASSWORD" \
>   --apple-id "you@example.com" \
>   --team-id "ABCD1234EF"
> ```

---

## Automated Releases (GitHub Actions)

When GitHub Actions are available, trigger a release from the **Actions** tab → **Release Binaries** → **Run workflow**.

The workflow runs on Ubuntu and uses `ldid` for ad-hoc macOS signing (no Apple account required in CI). For Developer ID signing in CI, set `CODESIGN_IDENTITY` as a GitHub Actions secret and add it to the workflow environment.

---

## License

Apache 2.0
