import Flutter
import UIKit
import KeychainAccess

public class FlutterUdidPlugin: NSObject, FlutterPlugin {

  public static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(name: "flutter_udid", binaryMessenger: registrar.messenger())
    let instance = FlutterUdidPlugin()
    registrar.addMethodCallDelegate(instance, channel: channel)
  }

  public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "getUDID":
      self.getUniqueDeviceIdentifierAsString(result: result)
    case "resetUDID":
      self.resetUDID(result: result)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  /// Accessibility for the stored UDID:
  /// - `afterFirstUnlock`: readable even while the device is locked (after the
  ///   first unlock since boot), so a launch from a locked/kiosk state cannot
  ///   fail to read the existing UDID.
  /// - `ThisDeviceOnly`: never migrates via backup/restore, preventing two
  ///   devices from ending up with the same UDID.
  private static let udidAccessibility: Accessibility = .afterFirstUnlockThisDeviceOnly

  private func makeKeychain() -> Keychain {
    let bundleName = Bundle.main.infoDictionary?["CFBundleName"] as? String ?? "flutter_udid"
    // Same service/account structure as the original SAMKeychain implementation
    // so existing users keep their UDID after upgrading.
    return Keychain(service: bundleName)
      .synchronizable(false)
      .accessibility(FlutterUdidPlugin.udidAccessibility)
  }

  private func resetUDID(result: FlutterResult) {
    let accountName = Bundle.main.bundleIdentifier ?? "com.default.app"
    let keychain = makeKeychain()

    // Delete device id stored in keychain
    do {
      try keychain.remove(accountName)
    } catch {
      // If the old value could not be removed, do NOT generate a new one —
      // that would leave two IDs alive (old in keychain, new in memory).
      result(FlutterError(code: "KEYCHAIN_UNAVAILABLE",
                          message: "Keychain remove failed: \(error)",
                          details: nil))
      return
    }

    // Generate and return a new device id
    self.getUniqueDeviceIdentifierAsString(result: result)
  }

  private func getUniqueDeviceIdentifierAsString(result: FlutterResult) {
    let accountName = Bundle.main.bundleIdentifier ?? "com.default.app"
    let keychain = makeKeychain()

    do {
      // KeychainAccess.get returns nil ONLY for errSecItemNotFound and throws
      // for every other status — so `nil` genuinely means "no UDID exists yet".
      if let applicationUUID = try keychain.get(accountName), !applicationUUID.isEmpty {
        self.upgradeLegacyAccessibilityIfNeeded(keychain, accountName, applicationUUID)
        result(applicationUUID)
        return
      }

      // No UDID stored yet (fresh install) — generate one and persist it.
      // Random UUID instead of identifierForVendor (see fork history).
      let applicationUUID = UUID().uuidString
      try keychain.set(applicationUUID, key: accountName)
      result(applicationUUID)
    } catch {
      // Transient keychain failure (device locked, errSecInteractionNotAllowed,
      // -34018, ...). NEVER generate a replacement UDID here — doing so rotates
      // the device identity and orphans everything keyed to the previous value.
      result(FlutterError(code: "KEYCHAIN_UNAVAILABLE",
                          message: "Keychain read/write failed: \(error)",
                          details: nil))
    }
  }

  /// Items written by older app versions used the default accessibility
  /// (`WhenUnlocked`), which is unreadable while the device is locked. Re-write
  /// the existing value once via SecItemUpdate (non-destructive) to upgrade it.
  /// Failures are intentionally ignored — an upgrade failure must never block
  /// or change the returned UDID.
  private func upgradeLegacyAccessibilityIfNeeded(
    _ keychain: Keychain, _ accountName: String, _ applicationUUID: String
  ) {
    let currentAccessibility = keychain[attributes: accountName]?.accessible
    if currentAccessibility != FlutterUdidPlugin.udidAccessibility.rawValue {
      try? keychain.set(applicationUUID, key: accountName)
    }
  }
}

