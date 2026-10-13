import AppKit
import Carbon.HIToolbox
import IOKit

/// Secure Input (password fields, some terminals) blocks keyboard listeners for every other app.
enum SecureInput {
    static var isEnabled: Bool { IsSecureEventInputEnabled() }

    /// Name of the app holding Secure Input, when macOS exposes it.
    static func ownerName() -> String? {
        let root = IORegistryGetRootEntry(kIOMainPortDefault)
        defer { IOObjectRelease(root) }
        guard let property = IORegistryEntryCreateCFProperty(root, "IOConsoleUsers" as CFString, kCFAllocatorDefault, 0),
              let users = property.takeRetainedValue() as? [[String: Any]] else {
            return nil
        }
        for user in users {
            if let pid = user["kCGSSessionSecureInputPID"] as? Int, pid > 0 {
                return NSRunningApplication(processIdentifier: pid_t(pid))?.localizedName ?? "PID \(pid)"
            }
        }
        return nil
    }
}
