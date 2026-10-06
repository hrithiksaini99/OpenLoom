import Foundation

enum Formatters {
    static func duration(_ seconds: Double) -> String {
        let value = seconds.isFinite ? Int(max(0, seconds)) : 0
        if value >= 3600 { return String(format: "%d:%02d:%02d", value / 3600, (value % 3600) / 60, value % 60) }
        return String(format: "%02d:%02d", value / 60, value % 60)
    }
}
