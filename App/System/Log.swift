import Foundation
import os

enum Log {
    static let subsystem = Bundle.main.bundleIdentifier ?? "com.hectormiko.quick-prompt"

    static let app = Logger(subsystem: subsystem, category: "app")
    static let trigger = Logger(subsystem: subsystem, category: "trigger")
    static let capture = Logger(subsystem: subsystem, category: "capture")
    static let output = Logger(subsystem: subsystem, category: "output")
    static let system = Logger(subsystem: subsystem, category: "system")
    static let prompts = Logger(subsystem: subsystem, category: "prompts")
}
