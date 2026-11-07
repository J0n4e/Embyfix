// One-time setup: creates the Ed25519 key pair that signs Cove updates.
//
//   swift scripts/make-update-key.swift
//
// Writes the private key to update-key.private (keep it secret: it becomes the COVE_UPDATE_KEY secret of the
// GitHub environment "release"; store a copy in your password manager, then delete the file) and prints the
// public key, which goes into Sources/Updater.swift (Updater.publicKey). Running it again makes a NEW key, which
// needs a key-rotation release first (RELEASING.md, "Changing the update key").
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
Private key written to update-key.private. Save a copy in your password manager, then:
  gh secret set COVE_UPDATE_KEY --env release -R J0n4e/cove < update-key.private
  rm update-key.private
(Replacing an existing key? Do the gh step only AFTER the key-rotation release is published; see RELEASING.md.)

Public key, for Sources/Updater.swift (static let publicKey = "..."):
  \(key.publicKey.rawRepresentation.base64EncodedString())
""")
