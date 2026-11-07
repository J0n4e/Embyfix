# Releasing Cove

Releases are built, signed and attested by GitHub Actions (`.github/workflows/build-app.yml`). The in-app
updater installs a release only if `Cove.zip.sig` verifies against the public key built into the app, so a
zip uploaded by hand (or by anyone who gets into the GitHub account) is refused.

## One-time setup (repository owner, on a Mac)

1. **Update-signing key** (Ed25519):
   ```sh
   swift scripts/make-update-key.swift
   gh secret set COVE_UPDATE_KEY -R J0n4e/cove < update-key.private
   ```
   Put the printed **public key** into `Sources/Updater.swift` (`static let publicKey = "..."`) in a PR.
   Save `update-key.private` in your password manager, then delete it. **Never commit it.**
2. **Code-signing certificate** (self-signed, gives every release the same identity, so Keychain items keep working
   across updates):
   ```sh
   scripts/make-signing-cert.sh --github     # creates cove-signing.p12 and sets CODESIGN_P12 / CODESIGN_P12_PASSWORD
   ```
   Save `cove-signing.p12` and its password in your password manager, then delete the file.
3. **Protect the branches** (Settings → Rules → Rulesets → New branch ruleset), for `main` and `Development`:
   *Restrict deletions*, *Block force pushes*, *Require a pull request before merging* (1 approval for `main`).
   Also turn on two-factor authentication for every account with write access, and
   *Settings → Code security → Private vulnerability reporting*.

Only the repository owner can add Actions secrets and rulesets.

## Each release

1. Merge `Development` into `main` (PR), as before.
2. Tag the merge commit and push the tag:
   ```sh
   git checkout main && git pull
   git tag v1.15.0 && git push origin v1.15.0
   ```
3. The workflow builds the app, signs it with the certificate, signs `Cove.zip` with the update key, adds a build
   attestation and creates a **draft** release with `Cove.zip` and `Cove.zip.sig`.
4. Open the draft on GitHub, write the release notes and **Publish**. Pre-releases are ignored by the updater.

Anyone can check that a download came from this repository's workflow:
`gh attestation verify Cove.zip -R J0n4e/cove`.

*Run workflow* on the Actions tab still builds a test artifact without creating a release.

## If a key leaks

- **Update key:** make a new pair, ship a release that contains the new public key (signed with the OLD key so
  current users can still update), then switch the secret to the new private key.
- **Certificate:** make a new one and update the two secrets. Users get a one-time Keychain prompt after the next update.
