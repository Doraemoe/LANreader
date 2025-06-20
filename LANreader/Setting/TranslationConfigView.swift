import ComposableArchitecture
import SwiftUI

@Reducer public struct TranslationConfigFeature {
    @ObservableState
    public struct State: Equatable {
        @Shared(.appStorage(SettingsKey.translationEnabled)) var translationEnabled = false
        @Shared(.appStorage(SettingsKey.translationUrl)) var translationUrl = ""
        @Shared(.appStorage(SettingsKey.translationService)) var translationService: TranslatorModel = .none
        @Shared(.appStorage(SettingsKey.translationTarget)) var translationLanguage: TargetLang = .CHS
    }
    public enum Action: BindableAction {
        case binding(BindingAction<State>)
    }

    public var body: some ReducerOf<Self> {
        BindingReducer()

        Reduce { _, action in
            switch action {
            default:
                return .none
            }
        }
    }
}

struct TranslationConfigView: View {
    @Bindable var store: StoreOf<TranslationConfigFeature>

    var navigation: NavigationHelper?

    var body: some View {
        Form {
            Section {
                Text("settings.advanced.translation.intro")
                    .multilineTextAlignment(.leading)
                    .padding()
            }
            Section {
                Toggle("settings.advantaged.translation.enabled", isOn: $store.translationEnabled)
                    .padding()

                if store.translationEnabled {
                    TextField("settings.advantaged.translation.url", text: $store.translationUrl)
                        .textContentType(.URL)
                        .keyboardType(.URL)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                        .padding()

                    Picker("settings.advantaged.translation.service", selection: $store.translationService) {
                        ForEach(TranslatorModel.allCases, id: \.self) { model in
                            Text(model.rawValue).tag(model)
                        }
                    }
                    .padding()

                    Picker("settings.advantaged.translation.language", selection: $store.translationLanguage) {
                        ForEach(TargetLang.allCases, id: \.self) { language in
                            Text(language.rawValue).tag(language)
                        }
                    }
                    .padding()
                }
            }
        }
        .padding(.top)
    }
}

class UITranslationConfigController: UIViewController {
    private let store: StoreOf<TranslationConfigFeature>
    private let navigation: NavigationHelper
    private var hostingController: UIHostingController<TranslationConfigView>!

    init(store: StoreOf<TranslationConfigFeature>, navigation: NavigationHelper) {
        self.store = store
        self.navigation = navigation
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    @objc override func viewDidLoad() {
        super.viewDidLoad()

        hostingController = UIHostingController(rootView: TranslationConfigView(store: store, navigation: navigation))
        hostingController.view.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(hostingController.view)
        NSLayoutConstraint.activate([
            hostingController.view.topAnchor.constraint(equalTo: view.topAnchor),
            hostingController.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            hostingController.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            hostingController.view.trailingAnchor.constraint(equalTo: view.trailingAnchor)
        ])
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        if #available(iOS 18.0, *) {
            tabBarController?.setTabBarHidden(true, animated: false)
        }
    }
}
