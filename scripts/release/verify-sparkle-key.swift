// Validate exported Sparkle keys without importing them into Keychain.
import Foundation
import CryptoKit

do {
    guard CommandLine.arguments.count == 3 else {
        throw NSError(domain: "Usage: verify-sparkle-key.swift KEY_FILE PUBLIC_KEY", code: 1)
    }
    let encoded = try String(contentsOfFile: CommandLine.arguments[1], encoding: .utf8)
        .trimmingCharacters(in: .whitespacesAndNewlines)
    guard let exported = Data(base64Encoded: encoded), [32, 96].contains(exported.count) else {
        throw NSError(domain: "Invalid Sparkle key export format", code: 1)
    }
    let key = try Curve25519.Signing.PrivateKey(rawRepresentation: exported.prefix(32))
    let publicKey = key.publicKey.rawRepresentation
    guard publicKey.base64EncodedString() == CommandLine.arguments[2],
          exported.count == 32 || exported.suffix(32) == publicKey else {
        throw NSError(domain: "Sparkle signing key does not match the app public key", code: 1)
    }
    print("Sparkle signing key matches the app.")
} catch {
    // Never print the key or input contents, including in error descriptions.
    fputs("Sparkle key validation failed. Check the export and SUPublicEDKey.\n", stderr)
    exit(1)
}
