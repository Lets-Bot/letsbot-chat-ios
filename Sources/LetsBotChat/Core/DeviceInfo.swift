import Foundation
#if canImport(UIKit)
import UIKit
#endif

/// Static facts about the host app and device that LetsBot needs (sent as headers / in `session` and `device`).
struct DeviceInfo: Equatable, Sendable {
    static let sdkVersion = "0.2.0"
    static let sdkHeader = "ios/\(sdkVersion)"
    static let platform = "ios"

    /// Bundle identifier, sent as `X-LB-App-Id`.
    var appId: String
    /// `CFBundleShortVersionString`.
    var appVersion: String?
    /// e.g. `"17.5"`.
    var osVersion: String

    static func current(bundle: Bundle = .main) -> DeviceInfo {
        let osVersion: String
        #if canImport(UIKit)
        osVersion = UIDevice.current.systemVersion
        #else
        let v = ProcessInfo.processInfo.operatingSystemVersion
        osVersion = "\(v.majorVersion).\(v.minorVersion).\(v.patchVersion)"
        #endif
        return DeviceInfo(
            appId: bundle.bundleIdentifier ?? "",
            appVersion: bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String,
            osVersion: osVersion
        )
    }
}

/// Works out whether an APNs device token belongs to the sandbox (development) or production APNs environment.
enum PushEnvironment {
    /// Sandbox detection order:
    /// 1. `aps-environment` in the app's `embedded.mobileprovision` (development → sandbox, production → not).
    /// 2. No profile, or no `aps-environment` in it: simulator or `DEBUG` build → sandbox; otherwise production
    ///    (App Store / TestFlight builds carry no `embedded.mobileprovision`).
    static func isSandbox(provisionData: Data?, isDebug: Bool, isSimulator: Bool) -> Bool {
        if let data = provisionData, let env = apsEnvironment(fromProvision: data) {
            return env == "development"
        }
        return isSimulator || isDebug
    }

    static var current: Bool {
        let url = Bundle.main.url(forResource: "embedded", withExtension: "mobileprovision")
        let data = url.flatMap { try? Data(contentsOf: $0) }
        #if DEBUG
        let isDebug = true
        #else
        let isDebug = false
        #endif
        #if targetEnvironment(simulator)
        let isSimulator = true
        #else
        let isSimulator = false
        #endif
        return isSandbox(provisionData: data, isDebug: isDebug, isSimulator: isSimulator)
    }

    /// Extracts `Entitlements.aps-environment` from a CMS-signed provisioning profile by locating the embedded
    /// XML plist (the profile is a PKCS#7 envelope around a plain XML plist).
    static func apsEnvironment(fromProvision data: Data) -> String? {
        guard let start = data.range(of: Data("<?xml".utf8)),
              let end = data.range(of: Data("</plist>".utf8), in: start.lowerBound..<data.endIndex)
        else { return nil }
        let plistData = data.subdata(in: start.lowerBound..<end.upperBound)
        guard let plist = try? PropertyListSerialization.propertyList(from: plistData, options: [], format: nil)
                as? [String: Any],
              let entitlements = plist["Entitlements"] as? [String: Any]
        else { return nil }
        return entitlements["aps-environment"] as? String
    }

    /// APNs device token → lowercase hex string.
    static func hex(_ deviceToken: Data) -> String {
        deviceToken.map { String(format: "%02x", $0) }.joined()
    }
}
