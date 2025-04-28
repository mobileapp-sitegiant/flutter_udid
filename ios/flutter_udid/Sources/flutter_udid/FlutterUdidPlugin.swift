import Flutter
import UIKit
import SAMKeychain

public class FlutterUdidPlugin: NSObject, FlutterPlugin {
  public static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(name: "flutter_udid", binaryMessenger: registrar.messenger())
    let instance = FlutterUdidPlugin()
    registrar.addMethodCallDelegate(instance, channel: channel)
  }

  public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "getUDID":
      self.getUniqueDeviceIdentifierAsString(result: result);
    case "resetUDID":
      self.resetUDID(result: result);
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private func getUniqueDeviceIdentifierAsString(result: FlutterResult) {
    let bundleName = Bundle.main.infoDictionary!["CFBundleName"] as! String
    let accountName = Bundle.main.bundleIdentifier!

    var applicationUUID = SAMKeychain.password(forService: bundleName, account: accountName)

    if applicationUUID == nil {
      applicationUUID = (UIDevice.current.identifierForVendor?.uuidString)!
      // original method get uuid from identifierForVendor, which cause duplicate uuid on some devices
      // applicationUUID = (UIDevice.current.identifierForVendor?.uuidString)!
      
      // Changed to generate random uuid
      let uuid = NSUUID().uuidString
      applicationUUID = uuid
      print("new uuid: \(uuid)")

      let query = SAMKeychainQuery()
      query.service = bundleName
      query.account = accountName
      query.password = applicationUUID
      query.synchronizationMode = SAMKeychainQuerySynchronizationMode.no

      do {
        try query.save()
      } catch let error as NSError {
        print("SAMKeychainQuery Exception: \(error)")
      }
    }

    if applicationUUID==nil||applicationUUID=="" {
      result(FlutterError.init(code: "UNAVAILABLE",
                               message: "UDID not available",
                               details: nil));
    } else {
      result(applicationUUID)
    }
  }

  private func resetUDID(result: FlutterResult){
    let bundleName = Bundle.main.infoDictionary!["CFBundleName"] as! String
    let accountName = Bundle.main.bundleIdentifier!
    
    // Delete device id stored in keychain
    SAMKeychain.deletePassword(forService: bundleName, account: accountName)
    
    // generate new device id
    self.getUniqueDeviceIdentifierAsString(result: result);
    
  }

}
