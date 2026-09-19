import Foundation
import os

// Журнал: unified log (сообщения публичные, без <private>) и ~/Library/Logs/BrowserPicker.log
enum Log {
    private static let logger = Logger(subsystem: "ru.devkz.browserpicker", category: "main")
    private static let fileURL = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("Logs/BrowserPicker.log")
    private static let queue = DispatchQueue(label: "ru.devkz.browserpicker.log")
    private static let stamp: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
        return f
    }()

    static func write(_ message: String) {
        logger.notice("\(message, privacy: .public)")
        let line = "\(stamp.string(from: Date())) \(message)\n"
        queue.async {
            // Не даём файлу расти бесконечно
            if let size = (try? FileManager.default.attributesOfItem(atPath: fileURL.path))?[.size] as? Int, size > 1_000_000 {
                try? FileManager.default.removeItem(at: fileURL)
            }
            if let handle = try? FileHandle(forWritingTo: fileURL) {
                handle.seekToEndOfFile()
                handle.write(Data(line.utf8))
                try? handle.close()
            } else {
                try? Data(line.utf8).write(to: fileURL)
            }
        }
    }
}
