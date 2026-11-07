// Signs a release zip for the in-app updater.
//
//   COVE_UPDATE_KEY=<base64 private key> swift scripts/sign-update.swift dist/Cove.zip [public key base64]
//
// Writes dist/Cove.zip.sig (the raw 64-byte Ed25519 signature), which is uploaded next to Cove.zip. With a
// public key it also checks that the key pair matches and the signature verifies, exactly as the app will.
import CryptoKit
import Foundation

func fail(_ m: String) -> Never {
    FileHandle.standardError.write(Data("sign-update: \(m)\n".utf8))
    exit(1)
}

let args = CommandLine.arguments
guard args.count >= 2 else { fail("usage: sign-update.swift <file> [public key base64]") }
let raw = (ProcessInfo.processInfo.environment["COVE_UPDATE_KEY"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
guard let kd = Data(base64Encoded: raw), let key = try? Curve25519.Signing.PrivateKey(rawRepresentation: kd) else {
    fail("COVE_UPDATE_KEY is missing or not a base64 Ed25519 private key")
}
let file = URL(fileURLWithPath: args[1])
guard let data = try? Data(contentsOf: file) else { fail("can't read \(file.path)") }
guard let sig = try? key.signature(for: data) else { fail("signing failed") }
let sigURL = file.appendingPathExtension("sig")
do { try sig.write(to: sigURL) } catch { fail("can't write \(sigURL.path)") }

if args.count >= 3 {
    guard let pd = Data(base64Encoded: args[2].trimmingCharacters(in: .whitespacesAndNewlines)),
          let pub = try? Curve25519.Signing.PublicKey(rawRepresentation: pd) else { fail("public key is not valid base64 Ed25519") }
    guard pub.rawRepresentation == key.publicKey.rawRepresentation else {
        fail("COVE_UPDATE_KEY does not belong to the public key in Sources/Updater.swift")
    }
    let back = (try? Data(contentsOf: sigURL)) ?? Data()
    guard pub.isValidSignature(back, for: data) else { fail("signature does not verify") }
    print("Signature verified against the app's public key.")
}
print("Signed \(file.lastPathComponent) -> \(sigURL.lastPathComponent) (\(sig.count) bytes)")
