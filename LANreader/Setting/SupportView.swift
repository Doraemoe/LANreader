import ComposableArchitecture
import SwiftUI
import StoreKit

@Reducer struct SupportFeature {
    @ObservableState
    struct State: Equatable {
        var loading = false
        var selectedSupportType: SupportType = .yearly
        var purchaseSuccess = false
    }

    enum Action: Equatable, BindableAction {
        case binding(BindingAction<State>)

        case startPurchase
        case finishedPurchase
        case setPurchaseSuccess
        case resetPurchaseSuccess
        case openTos
        case openPrivacy
    }

    @Dependency(\.openURL) var openURL

    var body: some ReducerOf<Self> {
        BindingReducer()

        Reduce { state, action in
            switch action {
            case .startPurchase:
                state.loading = true
                return .none
            case .finishedPurchase:
                state.loading = false
                return .none
            case .setPurchaseSuccess:
                state.purchaseSuccess = true
                return .run { send in
                    try await Task.sleep(for: .seconds(2))
                    await send(.resetPurchaseSuccess)
                }
            case .resetPurchaseSuccess:
                state.purchaseSuccess = false
                return .none
            case .openTos:
                return .run { _ in
                    await openURL(URL(string: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula")!)
                }
            case .openPrivacy:
                return .run { _ in
                    await openURL(URL(string: "https://github.com/Doraemoe/LANreader/blob/master/PRIVACY.md")!)
                }
            case .binding:
                return .none
            }
        }
    }

}

struct SupportView: View {
    @Bindable var store: StoreOf<SupportFeature>

    var body: some View {
        ZStack {
            VStack {
                Text("support.intro")
                    .multilineTextAlignment(.leading)
                    .padding()
                Picker("support.type", selection: $store.selectedSupportType) {
                    Text("support.yearly")
                        .tag(SupportType.yearly)
                    Text("support.one-time")
                        .tag(SupportType.oneTime)
                }
                .pickerStyle(.segmented)
                .padding()

                if store.selectedSupportType == .yearly {
                    SubscriptionStoreView(
                        productIDs: [IAP.yearlySnack.rawValue, IAP.yearlyTea.rawValue, IAP.yearlyDinner.rawValue]
                    )
                    .storeButton(.visible, for: .restorePurchases)
                    .storeButton(.hidden, for: .cancellation)
                    .subscriptionStoreControlStyle(.prominentPicker)
                    .onInAppPurchaseStart { _ in
                        store.send(.startPurchase)
                    }
                    .onInAppPurchaseCompletion { _, result in
                        store.send(.finishedPurchase)
                        if case .success(.success(let verificationResult)) = result {
                            switch verificationResult {
                            case .verified(let transaction):
                                await transaction.finish()
                                store.send(.setPurchaseSuccess)
                            case .unverified:
                                break
                            }
                        }
                    }
                } else {
                    StoreView(
                        ids: [IAP.oneTimeSnack.rawValue, IAP.oneTimeTea.rawValue, IAP.oneTimeDinner.rawValue]
                    ) { product in
                        if product.id == IAP.oneTimeSnack.rawValue {
                            Text("🍬")
                        } else if product.id == IAP.oneTimeTea.rawValue {
                            Text("🍵")
                        } else {
                            Text("🤯")
                        }
                    }
                    .storeButton(.hidden, for: .cancellation)
                    .productViewStyle(.compact)
                    .onInAppPurchaseStart { _ in
                        store.send(.startPurchase)
                    }
                    .onInAppPurchaseCompletion { _, result in
                        store.send(.finishedPurchase)
                        if case .success(.success(let verificationResult)) = result {
                            switch verificationResult {
                            case .verified(let transaction):
                                await transaction.finish()
                                store.send(.setPurchaseSuccess)
                            case .unverified:
                                break
                            }
                        }
                    }
                }
                HStack {
                    Button("support.tos") {
                        store.send(.openTos)
                    }
                    .font(.caption)
                    Text("support.and")
                        .font(.caption)
                    Button("support.privacy") {
                        store.send(.openPrivacy)
                    }
                    .font(.caption)
                }
            }
            if store.loading {
                Color.black.opacity(0.5)
                    .ignoresSafeArea()
                ProgressView()
                    .progressViewStyle(.circular)
                    .tint(.white)
            }
            if store.purchaseSuccess {
                Color.green.opacity(0.9)
                    .ignoresSafeArea()
                VStack {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.largeTitle)
                        .foregroundStyle(.white)
                    Text("support.thank")
                        .font(.title)
                        .bold()
                        .foregroundStyle(.white)
                }
            }
        }
    }
}

class UISupportViewController: UIViewController {
    private let store: StoreOf<SupportFeature>
    private var hostingController: UIHostingController<SupportView>!

    init(store: StoreOf<SupportFeature>) {
        self.store = store
        super.init(nibName: nil, bundle: nil)
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        self.hostingController = UIHostingController(rootView: SupportView(store: store))

        navigationItem.title = String(localized: "settings.support")

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
        }
    }
}

enum SupportType: String, CaseIterable, Identifiable {
    case yearly
    case oneTime

    var id: Self { self }
}

enum IAP: String, CaseIterable {
    case yearlySnack = "lanreader.yearly.low"
    case yearlyTea = "lanreader.yearly.median"
    case yearlyDinner = "lanreader.yearly.high"
    case oneTimeSnack = "lanreader.onetime.low"
    case oneTimeTea = "lanreader.onetime.median"
    case oneTimeDinner = "lanreader.onetime.high"
}
