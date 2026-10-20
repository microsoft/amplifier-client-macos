import Foundation
import CryptoKit

// The private seed arrives over stdin; only a success/failure message leaves.
let encoded = String(data: FileHandle.standardInput.readDataToEndOfFile(), encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
guard let seed = Data(base64Encoded: encoded), seed.count == 32,
      let expected = ProcessInfo.processInfo.environment["AMPLIFIER_UPDATE_PUBLIC_KEY"],
      let publicKey = Data(base64Encoded: expected), publicKey.count == 32,
      let key = try? Curve25519.Signing.PrivateKey(rawRepresentation: seed),
      key.publicKey.rawRepresentation == publicKey else {
    FileHandle.standardError.write(Data("Update signing seed does not match the app’s public key.\n".utf8))
    exit(1)
}
