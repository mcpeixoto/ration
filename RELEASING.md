# Releasing

Ration ships signed, self-updating builds. Two independent signatures are
involved and they do different jobs:

| Signature | Protects against | Where the key lives |
| --- | --- | --- |
| **Apple Developer ID** + notarisation | Gatekeeper refusing to launch the app | Apple, plus a CI secret |
| **Sparkle EdDSA** | A tampered update being installed | Your keychain, plus a CI secret |

The Sparkle key is the one that matters most: it means the download host is not
trusted. Even if GitHub Releases were compromised, an attacker could not make an
installed copy of Ration accept a modified build.

## One-time setup

### 1. Sparkle signing key

A key pair has already been generated and the public half is committed to
`Resources/sparkle_public_key.txt` (and baked into every build's `Info.plist`).
The private half is in your login keychain as **"Private key for signing Sparkle
updates"**.

Export it once for CI:

```sh
# Prints the private key. Do not paste this anywhere except the secret field.
./.build/artifacts/sparkle/Sparkle/bin/generate_keys -x -
```

Store the output as the `SPARKLE_PRIVATE_KEY` repository secret.

> **Back this key up.** Losing it means existing installs can never be updated
> again — you would have to ask everyone to re-download by hand. Keep a copy in
> a password manager.

### 2. Apple Developer ID

Export your Developer ID Application certificate as a `.p12`, then:

```sh
base64 -i certificate.p12 | pbcopy
```

### 3. Repository secrets

| Secret | Value |
| --- | --- |
| `SPARKLE_PRIVATE_KEY` | Output of `generate_keys -x -` |
| `CERTIFICATE_P12` | Base64 of your Developer ID `.p12` |
| `CERTIFICATE_PASSWORD` | Password you set when exporting the `.p12` |
| `KEYCHAIN_PASSWORD` | Any strong string; scopes the temporary CI keychain |
| `DEVELOPER_ID` | e.g. `Developer ID Application: Your Name (TEAMID)` |
| `APPLE_ID` | Your Apple ID email |
| `TEAM_ID` | Your 10-character Apple team ID |
| `APP_SPECIFIC_PASSWORD` | From appleid.apple.com, for notarisation |

## Cutting a release

```sh
echo "0.2.0" > VERSION       # must be > the current version
git commit -am "release: 0.2.0"
git tag v0.2.0
git push origin main --tags
```

The release workflow then:

1. runs the tests,
2. builds, signs, and notarises `Ration-0.2.0.dmg`,
3. signs the DMG with the Sparkle key,
4. prepends a signed `<item>` to `appcast.xml` and pushes it to `main`,
5. publishes the GitHub release with the DMG attached.

Installed copies poll `appcast.xml` once a day and offer the update.

## Verifying a release yourself

```sh
# Gatekeeper accepts it
spctl --assess --type execute -vv /Applications/Ration.app

# The bundled feed and key are the expected ones
/usr/libexec/PlistBuddy -c 'Print :SUFeedURL' -c 'Print :SUPublicEDKey' \
  /Applications/Ration.app/Contents/Info.plist

# The feed's signature verifies against the shipped public key
curl -s https://raw.githubusercontent.com/mcpeixoto/ration/main/appcast.xml
```

## If the signing key is ever compromised

1. Generate a new pair (`generate_keys -f`) and replace
   `Resources/sparkle_public_key.txt`.
2. Ship a release signed with the **old** key that contains the **new** public
   key — this is the last update existing installs can verify, so it has to be
   the one that hands over the new key.
3. Only then rotate `SPARKLE_PRIVATE_KEY` in CI.

Doing these out of order strands every existing install.
