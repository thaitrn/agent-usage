import Foundation
import ServiceManagement

/// "Open at Login" backed by SMAppService, which registers the app in
/// System Settings → General → Login Items. It needs a real .app bundle, so the
/// menu row hides itself when the binary is run straight from SwiftPM.
enum LoginItem {
    static var isAvailable: Bool {
        Bundle.main.bundleIdentifier != nil && SMAppService.mainApp.status != .notFound
    }

    static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    static func toggle() {
        do {
            if isEnabled {
                try SMAppService.mainApp.unregister()
            } else {
                try SMAppService.mainApp.register()
            }
        } catch {
            NSLog("Open at Login failed: \(error.localizedDescription)")
        }
    }
}
