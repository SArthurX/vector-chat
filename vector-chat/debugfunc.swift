import Foundation

func debuglog(_ message: String) {
    let formatter = DateFormatter()
    formatter.dateFormat = "HH:mm:ss"
    let timestamp = formatter.string(from: Date())
    print("\(timestamp) >>> \(message)")
}
