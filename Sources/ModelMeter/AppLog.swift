import Foundation
import os

enum AppLog {
    static let codex = Logger(subsystem: "com.bobkitchen.ModelMeter", category: "Codex")
    static let gemini = Logger(subsystem: "com.bobkitchen.ModelMeter", category: "Gemini")
    static let claude = Logger(subsystem: "com.bobkitchen.ModelMeter", category: "Claude")
    static let status = Logger(subsystem: "com.bobkitchen.ModelMeter", category: "ProviderStatus")
}
