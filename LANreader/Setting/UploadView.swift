import ComposableArchitecture
import SwiftUI
import Logging

@Reducer public struct UploadFeature: Sendable {
    private let logger = Logger(label: "UploadFeature")

    @ObservableState
    public struct State: Equatable {
        var urls = ""
        var jobDetails: [Int: DownloadJob] = .init()
        var isQueueing = false
        var retryingJobIDs: Set<Int> = []
        var retiredJobIDs: Set<Int> = []
    }

    public enum Action: Equatable, BindableAction, Sendable {
        case binding(BindingAction<State>)
        case queueDownload(String)
        case queueDownloadFinished([DownloadJob])
        case retryDownload(Int)
        case retryDownloadFinished(originalJobID: Int, jobs: [DownloadJob])
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
                state.isQueueing = true
                return .run { send in
                    let jobs = await queueDownloadJobs(urls)
                    await send(.queueDownloadFinished(jobs))
                }
            case let .queueDownloadFinished(jobs):
                state.isQueueing = false
                jobs.forEach {
                    state.retiredJobIDs.remove($0.id)
                    state.jobDetails[$0.id] = $0
                }
                return .none
            case let .retryDownload(id):
                guard let job = state.jobDetails[id],
                      job.isError,
                      !state.retryingJobIDs.contains(id)
                else {
                    return .none
                }
                state.retryingJobIDs.insert(id)
                return .run { send in
                    let jobs = await queueDownloadJobs(job.url)
                    if !jobs.isEmpty {
                        do {
                            _ = try database.deleteDownloadJobs(id)
                        } catch {
                            logger.error("failed to delete retried download job. id=\(id), \(error)")
                        }
                    }
                    await send(.retryDownloadFinished(originalJobID: id, jobs: jobs))
                }
            case let .retryDownloadFinished(originalJobID, jobs):
                state.retryingJobIDs.remove(originalJobID)
                if !jobs.isEmpty {
                    state.retiredJobIDs.insert(originalJobID)
                    state.jobDetails.removeValue(forKey: originalJobID)
                    jobs.forEach {
                        state.retiredJobIDs.remove($0.id)
                        state.jobDetails[$0.id] = $0
                    }
                }
                return .none
            case let .addJobDetails(jobs):
                jobs.forEach {
                    if !state.retiredJobIDs.contains($0.id) {
                        state.jobDetails[$0.id] = $0
                    }
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

    private func queueDownloadJobs(_ urls: String) async -> [DownloadJob] {
        var jobs: [DownloadJob] = .init()
        for url in urls.split(whereSeparator: \.isNewline) {
            let processedUrl = String(url).trimmingCharacters(in: .whitespacesAndNewlines)
            if !processedUrl.isEmpty {
                do {
                    let response = try await service.queueUrlDownload(downloadUrl: processedUrl).value
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
                    } else {
                        logger.warning("failed to queue download job. url=\(processedUrl)")
                    }
                } catch {
                    logger.error("failed to queue download job. url=\(processedUrl) \(error)")
                }
            }
        }
        return jobs
    }
}

struct UploadView: View {
    @Bindable var store: StoreOf<UploadFeature>

    var body: some View {
        ZStack {
            Color(uiColor: .systemGroupedBackground)
                .ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    uploadPanel
                    jobsSection
                    Text("settings.host.upload.note")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 24)
            }
        }
        .task {
            store.send(.checkJobStatus)
        }
        .toolbar(.hidden, for: .tabBar)
    }

    private var uploadPanel: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("settings.host.upload.label", systemImage: "link")
                .font(.headline)
                .foregroundStyle(.primary)

            TextEditor(text: $store.urls)
                .disableAutocorrection(true)
                .textInputAutocapitalization(.never)
                .scrollContentBackground(.hidden)
                .font(.body)
                .padding(12)
                .frame(minHeight: 128, maxHeight: 180)
                .background(
                    Color(uiColor: .tertiarySystemGroupedBackground),
                    in: RoundedRectangle(cornerRadius: 16, style: .continuous)
                )
                .overlay {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
                }

            Button(action: {
                store.send(.queueDownload(store.urls))
            }, label: {
                HStack(spacing: 8) {
                    if store.isQueueing {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Image(systemName: "arrow.up.circle.fill")
                    }
                    Text("settings.host.upload.action")
                        .fontWeight(.semibold)
                }
                .frame(maxWidth: .infinity)
            })
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(!hasUploadInput || store.isQueueing)
        }
        .padding(18)
        .background(
            Color(uiColor: .secondarySystemGroupedBackground),
            in: RoundedRectangle(cornerRadius: 24, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.06), lineWidth: 1)
        }
        .shadow(color: Color.black.opacity(0.05), radius: 16, x: 0, y: 8)
    }

    private var jobsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(sortedJobs) { detail in
                jobCard(detail)
            }

            if sortedJobs.isEmpty {
                emptyJobsView
            }
        }
    }

    private var emptyJobsView: some View {
        HStack(spacing: 12) {
            Image(systemName: "tray")
                .font(.title3.weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(width: 42, height: 42)
                .background(
                    Color(uiColor: .tertiarySystemGroupedBackground),
                    in: Circle()
                )

            Text("settings.host.upload.empty")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            Color(uiColor: .secondarySystemGroupedBackground),
            in: RoundedRectangle(cornerRadius: 20, style: .continuous)
        )
    }

    private func jobCard(_ detail: DownloadJob) -> some View {
        let status = status(for: detail)
        let isRetrying = store.retryingJobIDs.contains(detail.id)

        return VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                statusIcon(status)

                VStack(alignment: .leading, spacing: 6) {
                    Text(extractTitle(item: detail))
                        .font(.headline)
                        .foregroundStyle(.primary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)

                    Text(detail.url)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .textSelection(.enabled)

                    if !detail.message.isEmpty {
                        Text(detail.message)
                            .font(.subheadline)
                            .foregroundStyle(status.tint)
                            .lineLimit(3)
                    }
                }

                Spacer(minLength: 8)

                if detail.isError {
                    retryButton(jobID: detail.id, isRetrying: isRetrying)
                }
            }

            HStack(spacing: 8) {
                Text("download.job.id \(detail.id)")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)

                Spacer(minLength: 8)

                Text(status.titleKey)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(status.tint)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(status.tint.opacity(0.12), in: Capsule())
            }
        }
        .padding(16)
        .background(
            Color(uiColor: .secondarySystemGroupedBackground),
            in: RoundedRectangle(cornerRadius: 20, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.06), lineWidth: 1)
        }
    }

    private func statusIcon(_ status: UploadJobStatus) -> some View {
        Group {
            if status == .active {
                ProgressView()
                    .controlSize(.small)
            } else {
                Image(systemName: status.iconName)
                    .font(.system(size: 16, weight: .semibold))
            }
        }
        .foregroundStyle(status.tint)
        .frame(width: 42, height: 42)
        .background(status.tint.opacity(0.12), in: Circle())
    }

    private func retryButton(jobID: Int, isRetrying: Bool) -> some View {
        Button(action: {
            store.send(.retryDownload(jobID))
        }, label: {
            if isRetrying {
                ProgressView()
                    .controlSize(.small)
                    .frame(width: 42, height: 34)
            } else {
                Label("settings.host.upload.retry", systemImage: "arrow.clockwise")
                    .labelStyle(.iconOnly)
                    .frame(width: 42, height: 34)
            }
        })
        .buttonStyle(.bordered)
        .tint(.orange)
        .disabled(isRetrying)
    }

    private func extractTitle(item: DownloadJob) -> String {
        if item.title.isEmpty {
            return item.url
        }
        return item.title
    }

    private var sortedJobs: [DownloadJob] {
        store.jobDetails.values.sorted { $0.id < $1.id }
    }

    private var hasUploadInput: Bool {
        !store.urls.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func status(for detail: DownloadJob) -> UploadJobStatus {
        if detail.isActive {
            return .active
        }
        if detail.isSuccess {
            return .success
        }
        if detail.isError {
            return .failed
        }
        return .pending
    }

    private enum UploadJobStatus: Equatable {
        case active
        case success
        case failed
        case pending

        var iconName: String {
            switch self {
            case .active:
                return "arrow.triangle.2.circlepath"
            case .success:
                return "checkmark"
            case .failed:
                return "exclamationmark"
            case .pending:
                return "questionmark"
            }
        }

        var titleKey: LocalizedStringKey {
            switch self {
            case .active:
                return "settings.host.upload.status.active"
            case .success:
                return "settings.host.upload.status.success"
            case .failed:
                return "settings.host.upload.status.failed"
            case .pending:
                return "settings.host.upload.status.pending"
            }
        }

        var tint: Color {
            switch self {
            case .active:
                return .blue
            case .success:
                return .green
            case .failed:
                return .red
            case .pending:
                return .orange
            }
        }
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
        title = String(localized: "settings.host.upload")

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
        } else {
            tabBarController?.tabBar.isHidden = true
        }
    }
}
