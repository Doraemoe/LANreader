import ComposableArchitecture
import SwiftUI
import Logging

struct UploadFeature: Reducer {
    private let logger = Logger(label: "UploadFeature")

    struct State: Equatable {
        @BindingState var urls = ""
        var jobDetails: [Int: DownloadJob] = .init()
    }

    enum Action: Equatable, BindableAction {
        case binding(BindingAction<State>)
        case queueDownload(String)
        case addJobDetails([DownloadJob])
        case checkJobStatus
    }

    @Dependency(\.lanraragiService) var service
    @Dependency(\.appDatabase) var database
    @Dependency(\.continuousClock) var clock

    var body: some Reducer<State, Action> {
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
    let store: StoreOf<UploadFeature>

    var body: some View {
        WithViewStore(self.store, observe: { $0 }) { viewStore in
            GeometryReader { geometry in
                VStack {
                    Text("settings.host.upload.label")
                    TextEditor(text: viewStore.$urls)
                        .border(.secondary, width: 2)
                        .disableAutocorrection(true)
                        .padding()
                        .frame(maxHeight: geometry.size.height * 0.2)
                    Button(action: {
                        viewStore.send(.queueDownload(viewStore.urls))
                    }, label: {
                        Text("settings.host.upload.action")
                            .font(.title)
                    })
                    .buttonStyle(.borderedProminent)
                    List {
                        ForEach(viewStore.jobDetails.keys.sorted(), id: \.self) { key in
                            let detail = viewStore.jobDetails[key]!
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
                                            .foregroundColor(.green)
                                    } else if detail.isError {
                                        Image(systemName: "circle.fill")
                                            .foregroundColor(.red)
                                    } else {
                                        Image(systemName: "questionmark")
                                            .foregroundColor(.yellow)
                                    }
                                })
                            } header: {
                                Text("Job ID: \(key)")
                            }
                        }
                        Text("settings.host.upload.note")
                            .font(.footnote)
                    }

                }
                .task {
                    viewStore.send(.checkJobStatus)
                }
                .toolbar(.hidden, for: .tabBar)
            }
        }
    }

    private func extractTitle(item: DownloadJob) -> String {
        if item.title.isEmpty {
            return item.url
        }
        return item.title
    }
}
