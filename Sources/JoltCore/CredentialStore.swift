import Foundation
import Security

public protocol CredentialStoring: AnyObject {
  func data(for key: String) throws -> Data?
  func set(_ data: Data, for key: String) throws
  func remove(_ key: String) throws
}

public protocol CacheManaging: AnyObject {
  func clear() async throws
}

public enum CredentialStoreError: LocalizedError {
  case unexpectedStatus(OSStatus)

  public var errorDescription: String? {
    switch self {
    case .unexpectedStatus(let status):
      let message = SecCopyErrorMessageString(status, nil) as String? ?? "Unknown Keychain error"
      return "Keychain error: \(message) (\(status))"
    }
  }
}

public final class KeychainCredentialStore: CredentialStoring, @unchecked Sendable {
  private let service: String

  public init(service: String = "co.simonsc.jolt") {
    self.service = service
  }

  public func data(for key: String) throws -> Data? {
    var query = baseQuery(for: key)
    query[kSecReturnData as String] = true
    query[kSecMatchLimit as String] = kSecMatchLimitOne
    // Credential restoration happens during launch. Never let that background
    // lookup surprise the user with a system authorization dialog. If an older
    // build no longer satisfies the item's access control, the app starts in
    // its disconnected state and asks for credentials in its own UI instead.
    query[kSecUseAuthenticationUI as String] = kSecUseAuthenticationUISkip

    var result: CFTypeRef?
    let status = SecItemCopyMatching(query as CFDictionary, &result)
    if status == errSecItemNotFound { return nil }
    guard status == errSecSuccess else { throw CredentialStoreError.unexpectedStatus(status) }
    return result as? Data
  }

  public func set(_ data: Data, for key: String) throws {
    let query = baseQuery(for: key)
    let update = [kSecValueData as String: data]
    let updateStatus = SecItemUpdate(query as CFDictionary, update as CFDictionary)

    if updateStatus == errSecItemNotFound {
      var insertion = query
      insertion[kSecValueData as String] = data
      insertion[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
      let addStatus = SecItemAdd(insertion as CFDictionary, nil)
      guard addStatus == errSecSuccess else {
        throw CredentialStoreError.unexpectedStatus(addStatus)
      }
    } else if updateStatus != errSecSuccess {
      throw CredentialStoreError.unexpectedStatus(updateStatus)
    }
  }

  public func remove(_ key: String) throws {
    let status = SecItemDelete(baseQuery(for: key) as CFDictionary)
    guard status == errSecSuccess || status == errSecItemNotFound else {
      throw CredentialStoreError.unexpectedStatus(status)
    }
  }

  private func baseQuery(for key: String) -> [String: Any] {
    [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: service,
      kSecAttrAccount as String: key,
    ]
  }
}

extension CredentialStoring {
  public func codableValue<T: Codable>(_ type: T.Type, for key: String) throws -> T? {
    guard let data = try data(for: key) else { return nil }
    return try JSONDecoder().decode(type, from: data)
  }

  public func setCodableValue<T: Codable>(_ value: T, for key: String) throws {
    try set(JSONEncoder().encode(value), for: key)
  }
}
