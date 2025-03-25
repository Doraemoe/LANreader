import ComposableArchitecture
import SwiftUI
import StoreKit

@Reducer struct SupportFeature {
    @ObservableState
    struct State: Equatable {
        var selectedSupportType: SupportType = .yearly
    }

    enum Action: Equatable, BindableAction {
        case binding(BindingAction<State>)
    }

    var body: some ReducerOf<Self> {
        BindingReducer()

        Reduce { _, action in
            switch action {
            case .binding:
                return .none
            }
        }
    }

}

struct SupportView: View {
    @Bindable var store: StoreOf<SupportFeature>

    var body: some View {
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
