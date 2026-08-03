import UIKit
import XCTest
@testable import LANreader

final class LogTextRendererTests: XCTestCase {
    // Puppy writes CRLF line endings and "\r\n" is a single Swift Character,
    // so every entry must still be highlighted independently.
    func testEachCarriageReturnSeparatedEntryIsHighlighted() {
        let log = [
            "timestamp=2026-07-29T11:00:00.000+10:00 level=info logger=a location=b#L.1 function=c() message=first",
            "timestamp=2026-07-29T11:00:01.000+10:00 level=error logger=a location=b#L.2 function=c() message=second"
        ].joined(separator: "\r\n") + "\r\n"

        let attributed = LogTextRenderer.attributedLog(from: log)

        XCTAssertEqual(levelValueColors(in: attributed), [.systemBlue, .systemRed])
    }

    func testLineFeedSeparatedEntriesAreHighlighted() {
        let log = [
            "timestamp=2026-07-29T11:00:00.000+10:00 level=warning logger=a location=b#L.1 function=c() message=first",
            "timestamp=2026-07-29T11:00:01.000+10:00 level=info logger=a location=b#L.2 function=c() message=second"
        ].joined(separator: "\n")

        let attributed = LogTextRenderer.attributedLog(from: log)

        XCTAssertEqual(levelValueColors(in: attributed), [.systemOrange, .systemBlue])
    }

    func testRenderedTextPreservesEveryEntry() {
        let log = "level=info message=first\r\nlevel=info message=second\r\n"

        let rendered = LogTextRenderer.attributedLog(from: log).string

        XCTAssertEqual(
            rendered.split(omittingEmptySubsequences: true, whereSeparator: \.isNewline),
            ["level=info message=first", "level=info message=second"]
        )
    }

    private func levelValueColors(in attributed: NSAttributedString) -> [UIColor] {
        var colors: [UIColor] = []
        let text = attributed.string as NSString

        attributed.enumerateAttribute(
            .foregroundColor,
            in: NSRange(location: 0, length: attributed.length)
        ) { value, range, _ in
            guard let color = value as? UIColor else { return }
            guard levelValues(in: text).contains(text.substring(with: range)) else { return }
            colors.append(color)
        }

        return colors
    }

    private func levelValues(in text: NSString) -> Set<String> {
        ["trace", "debug", "info", "notice", "warning", "warn", "error", "critical", "fatal"]
            .filter { text.contains("level=\($0)") }
            .reduce(into: Set<String>()) { $0.insert($1) }
    }
}
