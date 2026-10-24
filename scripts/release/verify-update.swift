#!/usr/bin/env swift
// Independently bind the archive signature to the public key shipped in Info.plist.
import CryptoKit
import Foundation

func verify() throws {
    let arguments = CommandLine.arguments
    guard arguments.count == 4,
          let signature = Data(base64Encoded: arguments[2]),
          let rawKey = Data(base64Encoded: arguments[3]) else {
        throw CocoaError(.fileReadCorruptFile)
    }
    let archive = try Data(contentsOf: URL(fileURLWithPath: arguments[1]), options: .mappedIfSafe)
    let key = try Curve25519.Signing.PublicKey(rawRepresentation: rawKey)
    guard key.isValidSignature(signature, for: archive) else {
        throw CocoaError(.fileReadCorruptFile)
    }
}

do {
    try verify()
} catch {
    fputs("Update signature does not match the archive and source public key.\n", stderr)
    exit(1)
}
