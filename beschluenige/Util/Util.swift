//
//  Util.swift
//  beschluenige
//
//  Created by Eleanor McMurtry on 13.02.2026.
//
import CryptoKit
import Foundation

nonisolated func md5Hex(of url: URL) throws -> String {
    let data = try Data(contentsOf: url)
    let digest = Insecure.MD5.hash(data: data)
    return digest.map { String(format: "%02x", $0) }.joined()
}
