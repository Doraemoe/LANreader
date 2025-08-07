import ComposableArchitecture
import SwiftUI
import Logging

@Reducer public struct UploadFeature {
    private let logger = Logger(label: "UploadFeature")

    @ObservableState
    public struct State: Equatable {
        var urls = ""
        var jobDetails: [Int: DownloadJob] = .init()
    }

    public enum Action: Equatable, BindableAction {
        case binding(BindingAction<State>)
        case queueDownload(String)
        case addJobDetails([DownloadJob])
        case checkJobStatus
    }

    @Dependency(\.lanraragiService) var service
    @Dependency(\.appDatabase) var database
    @Dependency(\.continuousClock) var clock

    public var body: some Reducer<State, Action> {
        BindingReducer()
        Reduce { state, action in
            switch action {
            case let .queueDownload(urls):
                return .run { send in
                    var jobs: [DownloadJob] = .init()
                    for url in urls.split(whereSeparator: \.isNewline) {
                        let processedUrl = url.trimmingCharacters(in: .whitespaces)
                        if !processedUrl.isEmpty {
                            do {
                                let response = try await service.queueUrlDownload(downloadUrl: String(url)).value
                                if response.success == 1 {
                                    var downloadJob = DownloadJob(
                                        id: response.job,
                                        url: response.url,
                                        title: "",
                                        isActive: true,
                                        isSuccess: false,
                                        isError: false,
                                        message: "",
                                        lastUpdate: Date()
                                    )
                                    try? database.saveDownloadJob(&downloadJob)
                                    jobs.append(downloadJob)
                                }
                            } catch {
                                logger.error("failed to queue download job. url=\(url) \(error)")
                            }
                        }
                    }
                    await send(.addJobDetails(jobs))
                }
            case let .addJobDetails(jobs):
                jobs.forEach {
                    state.jobDetails[$0.id] = $0
                }
                return .none
            case .checkJobStatus:
                return .run { send in
                    repeat {
                        let downloadJobs: [DownloadJob]
                        do {
                            downloadJobs = try database.readAllDownloadJobs()
                        } catch {
                            logger.error("failed to retrieve download jobs from db. \(error)")
                            downloadJobs = .init()
                        }
                        var updatedJobs: [DownloadJob] = .init()
                        for job in downloadJobs {
                            if job.lastUpdate.addingTimeInterval(3600) < Date() {
                                _ = try? database.deleteDownloadJobs(job.id)
                            }
                            if !job.isSuccess && !job.isError {
                                do {
                                    let response = try await service.checkJobStatus(id: job.id).value
                                    var downloadJob = response.toDownloadJob(url: job.url)
                                    updatedJobs.append(downloadJob)
                                    do {
                                        try database.saveDownloadJob(&downloadJob)
                                    } catch {
                                        logger.error("failed to save updated job to database. id=\(job.id), \(error)")
                                    }
                                } catch {
                                    logger.error("failed to check job status. id=\(job.id) \(error)")
                                }
                            } else {
                                updatedJobs.append(job)
                            }
                        }
                        await send(.addJobDetails(updatedJobs))
                        try await clock.sleep(for: .seconds(5))
                    } while true
                }
            case .binding:
                return .none
            }
        }
    }
}

struct UploadView: View {
    @Bindable var store: StoreOf<UploadFeature>

    var body: some View {
        GeometryReader { geometry in
            VStack {
                Text("settings.host.upload.label")
                TextEditor(text: $store.urls)
                    .border(.secondary, width: 2)
                    .disableAutocorrection(true)
                    .padding()
                    .frame(maxHeight: geometry.size.height * 0.2)
                Button(action: {
                    store.send(.queueDownload(store.urls))
                }, label: {
                    Text("settings.host.upload.action")
                        .font(.title)
                })
                .buttonStyle(.borderedProminent)
                List {
                    ForEach(store.jobDetails.keys.sorted(), id: \.self) { key in
                        let detail = store.jobDetails[key]!
                        Section {
                            Label(title: {
                                VStack {
                                    Text(extractTitle(item: detail))
                                    Text(detail.message)
                                }
                            }, icon: {
                                if detail.isActive {
                                    ProgressView()
                                } else if detail.isSuccess {
                                    Image(systemName: "circle.fill")
                                        .foregroundStyle(.green)
                                } else if detail.isError {
                                    Image(systemName: "circle.fill")
                                        .foregroundStyle(.red)
                                } else {
                                    Image(systemName: "questionmark")
                                        .foregroundStyle(.yellow)
                                }
                            })
                        } header: {
                            Text("download.job.id \(key)")
                        }
                    }
                    Text("settings.host.upload.note")
                        .font(.footnote)
                }
            }
            .task {
                store.send(.checkJobStatus)
            }
            .toolbar(.hidden, for: .tabBar)
        }
    }

    private func extractTitle(item: DownloadJob) -> String {
        if item.title.isEmpty {
            return item.url
        }
        return item.title
    }
}

class UIUploadViewController: UIViewController {
    private let store: StoreOf<UploadFeature>

    init(store: StoreOf<UploadFeature>) {
        self.store = store
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        let hostingController = UIHostingController(
            rootView: UploadView(store: store)
        )

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
        }
    }
}
