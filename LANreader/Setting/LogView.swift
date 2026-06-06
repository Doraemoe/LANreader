//
//  Created on 17/9/21.
//
import ComposableArchitecture
import SwiftUI

@Reducer public struct LogFeature {
    @ObservableState
    public struct State: Equatable {
        var log = ""
    }

    public enum Action: Equatable {
        case setLog(String)
    }

    public var body: some Reducer<State, Action> {
        Reduce { state, action in
            switch action {
            case let .setLog(log):
                state.log = log
                return .none
            }
        }
    }
}

struct LogView: View {

    let store: StoreOf<LogFeature>

    var body: some View {
        SelectableLogTextView(attributedLog: LogTextRenderer.attributedLog(from: store.log))
            .ignoresSafeArea(.keyboard, edges: .bottom)
        .background(Color(.systemGroupedBackground))
        .onAppear(perform: {
            do {
                let logFileURL = try FileManager.default
                    .url(
                        for: .applicationSupportDirectory,
                        in: .userDomainMask,
                        appropriateFor: nil,
                        create: true
                    )
                    .appendingPathComponent("app.log")
                let log = try String(contentsOf: logFileURL, encoding: .utf8)
                store.send(.setLog(log))
            } catch {
                store.send(.setLog("error reading log"))
            }
        })
        .toolbar(.hidden, for: .tabBar)
    }
}

private struct SelectableLogTextView: UIViewRepresentable {
    let attributedLog: NSAttributedString

    func makeUIView(context: Context) -> UITextView {
        let textView = UITextView()
        textView.backgroundColor = .systemGroupedBackground
        textView.isEditable = false
        textView.isSelectable = true
        textView.isScrollEnabled = true
        textView.alwaysBounceVertical = true
        textView.adjustsFontForContentSizeCategory = true
        textView.textContainerInset = UIEdgeInsets(top: 16, left: 16, bottom: 16, right: 16)
        textView.textContainer.lineFragmentPadding = 0
        return textView
    }

    func updateUIView(_ textView: UITextView, context: Context) {
        textView.attributedText = attributedLog
    }
}

private enum LogTextRenderer {
    private static let messageMarker = " message="

    static func attributedLog(from log: String) -> NSAttributedString {
        let attributedLog = NSMutableAttributedString()
        let lines = log.split(separator: "\n", omittingEmptySubsequences: false)

        for (index, line) in lines.enumerated() {
            attributedLog.append(attributedLine(from: String(line)))
            if index < lines.count - 1 {
                attributedLog.append(segment("\n", color: .label))
            }
        }

        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.lineSpacing = 3
        attributedLog.addAttributes(
            [.paragraphStyle: paragraphStyle],
            range: NSRange(location: 0, length: attributedLog.length)
        )

        return attributedLog
    }

    // Mirrors LogFormatter's ordered key=value output while keeping malformed lines readable.
    private static func attributedLine(from line: String) -> NSAttributedString {
        guard let messageRange = line.range(of: messageMarker) else {
            return segment(line, color: .label)
        }

        let attributedLine = NSMutableAttributedString()
        let metadata = line[..<messageRange.lowerBound]
        let message = line[messageRange.upperBound...]

        for field in metadata.split(separator: " ", omittingEmptySubsequences: false) {
            appendField(String(field), to: attributedLine)
            attributedLine.append(segment(" ", color: .secondaryLabel))
        }

        appendField("message=\(message)", to: attributedLine)
        return attributedLine
    }

    private static func appendField(_ field: String, to attributedLine: NSMutableAttributedString) {
        guard let separatorIndex = field.firstIndex(of: "=") else {
            attributedLine.append(segment(field, color: .label))
            return
        }

        let key = String(field[..<separatorIndex])
        let value = String(field[field.index(after: separatorIndex)...])

        attributedLine.append(segment("\(key)=", color: .secondaryLabel))
        attributedLine.append(segment(value, color: valueColor(for: key, value: value)))
    }

    private static func valueColor(for key: String, value: String) -> UIColor {
        switch key {
        case "timestamp":
            return .systemTeal
        case "level":
            return levelColor(value)
        case "logger":
            return .systemIndigo
        case "location":
            return .systemPurple
        case "function":
            return .systemGreen
        case "message":
            return .label
        default:
            return .label
        }
    }

    private static func levelColor(_ level: String) -> UIColor {
        switch level.lowercased() {
        case "trace":
            return .secondaryLabel
        case "debug":
            return .systemPurple
        case "info":
            return .systemBlue
        case "notice":
            return .systemIndigo
        case "warning", "warn":
            return .systemOrange
        case "error", "critical", "fatal":
            return .systemRed
        default:
            return .label
        }
    }

    private static func segment(_ text: String, color: UIColor) -> NSAttributedString {
        NSAttributedString(
            string: text,
            attributes: [
                .font: UIFontMetrics(forTextStyle: .caption1).scaledFont(
                    for: .monospacedSystemFont(ofSize: 12, weight: .regular)
                ),
                .foregroundColor: color
            ]
        )
    }
}

class UILogViewController: UIViewController {
    private let store: StoreOf<LogFeature>
    private var hostingController: UIHostingController<LogView>!

    init(store: StoreOf<LogFeature>) {
        self.store = store
        super.init(nibName: nil, bundle: nil)
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        self.hostingController = UIHostingController(rootView: LogView(store: store))

        add(hostingController)
        NSLayoutConstraint.activate([
            hostingController!.view.topAnchor.constraint(equalTo: view.topAnchor),
            hostingController!.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            hostingController!.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            hostingController!.view.trailingAnchor.constraint(equalTo: view.trailingAnchor)
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        if #available(iOS 18.0, *) {
            tabBarController?.setTabBarHidden(true, animated: false)
        } else {
            tabBarController?.tabBar.isHidden = true
        }
    }
}
