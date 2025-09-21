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
            ScrollView {
                Text(store.log)
                    .textSelection(.enabled)
            }
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
