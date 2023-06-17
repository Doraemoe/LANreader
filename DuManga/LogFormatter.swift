import Foundation
import Puppy

struct LogFormatter: LogFormattable {
    private let dateFormat = DateFormatter()

    init() {
        dateFormat.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSSZZZZZ"
    }

    // swiftlint:disable all
    func formatMessage(_ level: LogLevel, message: String, tag: String, function: String,
                       file: String, line: UInt, swiftLogInfo: [String: String],
                       label: String, date: Date, threadID: UInt64) -> String {
        let date = dateFormatter(date, withFormatter: dateFormat)
        let fileName = fileName(file)
        let moduleName = moduleName(file)
        return "timestamp=\(date) level=\(level) logger=\(swiftLogInfo["label"] ?? "") location=\(moduleName)/\(fileName)#L.\(line) function=\(function) message=\(message)"
    }
    // swiftlint:enable all
}
