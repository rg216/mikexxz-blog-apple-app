import Foundation
import Security

/// 后台 token 存在钥匙串里（不放 UserDefaults：那是明文 plist，会进 iCloud / 电脑备份）。
/// 只在这台设备上、解锁过一次之后可读（ThisDeviceOnly：不随备份迁移到别的设备）
enum TokenStore {
  private static let service = "com.mikexxz.Blog.admin"
  private static let account = "session"

  static func load() -> String? {
    var query = baseQuery()
    query[kSecReturnData as String] = true
    query[kSecMatchLimit as String] = kSecMatchLimitOne
    var result: AnyObject?
    var status = SecItemCopyMatching(query as CFDictionary, &result)
    if status == errSecMissingEntitlement {
      query[kSecUseDataProtectionKeychain as String] = nil
      status = SecItemCopyMatching(query as CFDictionary, &result)
    }
    guard status == errSecSuccess, let data = result as? Data else { return nil }
    return String(data: data, encoding: .utf8)
  }

  static func save(_ token: String) {
    delete()
    var item = baseQuery()
    item[kSecValueData as String] = Data(token.utf8)
    item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
    if SecItemAdd(item as CFDictionary, nil) == errSecMissingEntitlement {
      item[kSecUseDataProtectionKeychain as String] = nil
      SecItemAdd(item as CFDictionary, nil)
    }
  }

  static func delete() {
    var query = baseQuery()
    SecItemDelete(query as CFDictionary)
    query[kSecUseDataProtectionKeychain as String] = nil
    SecItemDelete(query as CFDictionary)
  }

  /// macOS 上用"数据保护钥匙串"（和 iOS 同一套）；没有正式签名（本地运行的 ad-hoc 签名）时它报
  /// errSecMissingEntitlement，退回传统的文件钥匙串
  private static func baseQuery() -> [String: Any] {
    [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: service,
      kSecAttrAccount as String: account,
      kSecUseDataProtectionKeychain as String: true,
    ]
  }
}
