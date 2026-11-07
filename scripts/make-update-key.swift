// One-time setup: creates the Ed25519 key pair that signs Cove updates.
//
//   swift scripts/make-update-key.swift
//
// Writes the private key to update-key.private (keep it secret: add it as the GitHub Actions secret
// COVE_UPDATE_KEY, store a copy in your password manager, then delete the file) and prints the public key,
// which goes into Sources/Updater.swift (Updater.publicKey). Running it again makes a NEW key: apps that
// have the old public key would then refuse every update, so only do that if the private key leaked.
import CryptoKit
import Foundation

let out = URL(fileURLWithPath: "update-key.private")
guard !FileManager.default.fileExists(atPath: out.path) else {
    FileHandle.standardError.write(Data("update-key.private already exists; not overwriting it.\n".utf8))
    exit(1)
}
let key = Curve25519.Signing.PrivateKey()
try Data(key.rawRepresentation.base64EncodedString().utf8).write(to: out)
try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: out.path)

print("""
Private key written to update-key.private. Next:
  gh secret set COVE_UPDATE_KEY -R J0n4e/cove < update-key.private
  (save a copy in your password manager, then: rm update-key.private)

Public key, for Sources/Updater.swift (static let publicKey = "..."):
  \(key.publicKey.rawRepresentation.base64EncodedString())
""")
