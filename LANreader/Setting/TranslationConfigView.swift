import ComposableArchitecture
import SwiftUI

@Reducer public struct TranslationConfigFeature {
    @ObservableState
    public struct State: Equatable {
        @Shared(.appStorage(SettingsKey.translationEnabled)) var translationEnabled = false
        @Shared(.appStorage(SettingsKey.translationUrl)) var translationUrl = ""
        @Shared(.appStorage(SettingsKey.translationService)) var translationService: TranslatorModel = .none
        @Shared(.appStorage(SettingsKey.translationTarget)) var translationLanguage: TargetLang = .CHS
        @Shared(.appStorage(SettingsKey.translationUnclipRatio)) var unclipRatio = 2.3
        @Shared(.appStorage(SettingsKey.translationBoxThreshold)) var boxThreshold = 0.7
        @Shared(.appStorage(SettingsKey.translationMaskDilationOffset)) var maskDilationOffset = 30
        @Shared(.appStorage(SettingsKey.translationDetectionResolution))
        var detectionResolution: DetectionResolution = .res1536
        @Shared(.appStorage(SettingsKey.translationTextDetector)) var textDetector: TextDetector = .default
        @Shared(.appStorage(SettingsKey.translationRenderTextDirection)) var renderTextDirection: TextDirection = .auto
        @Shared(.appStorage(SettingsKey.translationInpaintingSize)) var inpaintingSize: InpainterSize = .size2048
        @Shared(.appStorage(SettingsKey.translationInpainter)) var inpainter: Inpainter = .lama_large
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

                    Picker(
                        "settings.advantaged.translation.detectionResolution", selection: $store.detectionResolution
                    ) {
                        ForEach(DetectionResolution.allCases, id: \.self) { resolution in
                            Text("\(resolution.rawValue)").tag(resolution)
                        }
                    }
                    .padding()

                    Picker("settings.advantaged.translation.textDetector", selection: $store.textDetector) {
                        ForEach(TextDetector.allCases, id: \.self) { detector in
                            Text(detector.rawValue).tag(detector)
                        }
                    }
                    .padding()

                    Picker(
                        "settings.advantaged.translation.renderTextDirection", selection: $store.renderTextDirection
                    ) {
                        ForEach(TextDirection.allCases, id: \.self) { direction in
                            Text(direction.rawValue).tag(direction)
                        }
                    }
                    .padding()

                    Picker("settings.advantaged.translation.inpaintingSize", selection: $store.inpaintingSize) {
                        ForEach(InpainterSize.allCases, id: \.self) { size in
                            Text("\(size.rawValue)").tag(size)
                        }
                    }
                    .padding()

                    Picker("settings.advantaged.translation.inpainter", selection: $store.inpainter) {
                        ForEach(Inpainter.allCases, id: \.self) { inpainter in
                            Text(inpainter.rawValue).tag(inpainter)
                        }
                    }
                    .padding()

                    LabeledContent {
                        TextField(
                            "settings.advantaged.translation.unclipRatio", value: $store.unclipRatio, format: .number
                        )
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                    } label: {
                        Text("settings.advantaged.translation.unclipRatio")
                    }
                    .padding()

                    LabeledContent {
                        TextField(
                            "settings.advantaged.translation.boxThreshold", value: $store.boxThreshold, format: .number
                        )
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                    } label: {
                        Text("settings.advantaged.translation.boxThreshold")
                    }
                    .padding()

                    LabeledContent {
                        TextField(
                            "settings.advantaged.translation.maskDilationOffset",
                            value: $store.maskDilationOffset,
                            format: .number
                        )
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                    } label: {
                        Text("settings.advantaged.translation.maskDilationOffset")
                    }
                    .padding()
                }
            }
        }
        .toolbar(.hidden, for: .tabBar)
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
        add(hostingController)
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
        } else {
            tabBarController?.tabBar.isHidden = true
        }
    }
}
