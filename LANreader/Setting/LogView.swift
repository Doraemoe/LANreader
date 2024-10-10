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
