import ComposableArchitecture
import SwiftUI
import Logging

@Reducer struct ArchiveDetailsFeature {
    private let logger = Logger(label: "ArchiveDetailsFeature")

    struct State: Equatable {
        @PresentationState var alert: AlertState<Action.Alert>?
        var id: String
        @BindingState var editMode: EditMode = .inactive
        @BindingState var title = ""
        @BindingState var tags = ""
        var errorMessage = ""
        var archiveMetadata: ArchiveMetadata?
        var loading = false
    }

    enum Action: Equatable, BindableAction {
        case binding(BindingAction<State>)
        case alert(PresentationAction<Alert>)

        case loadMetadata
        case setArchiveMetadata(ArchiveMetadata)
        case setErrorMessage(String)

        case deleteButtonTapped
        case deleteSuccess
        enum Alert {
            case confirmDelete
        }
    }

    @Dependency(\.lanraragiService) var service
    @Dependency(\.appDatabase) var database

    var body: some ReducerOf<Self> {
        BindingReducer()

        Reduce { state, action in
            switch action {
            case .loadMetadata:
                state.loading = true
                return .run { [state] send in
                    let metadata = try await service.retrieveArchiveMetadata(id: state.id).value
                    let thumbnailData = try database.readArchiveThumbnail(state.id)
                    await send(
                        .setArchiveMetadata(
                            ArchiveMetadata(
                                title: metadata.title, archiveThumbnail: thumbnailData, tags: metadata.tags ?? ""
                            )
                        )
                    )
                } catch: { [state] error, send in
                    logger.error("failed to load archive details. id=\(state.id) \(error)")
                    await send(.setErrorMessage(error.localizedDescription))
                }
            case let .setArchiveMetadata(metadata):
                state.archiveMetadata = metadata
                state.title = metadata.title
                state.tags = metadata.tags
                state.loading = false
                return .none
            case let .setErrorMessage(message):
                state.errorMessage = message
                state.loading = false
                return .none
            case .deleteButtonTapped:
                state.alert = AlertState {
                    TextState("archive.delete.confirm")
                } actions: {
                    ButtonState(role: .destructive, action: .confirmDelete) {
                        TextState("delete")
                    }
                    ButtonState(role: .cancel) {
                        TextState("cancel")
                    }
                }
                return .none
            case .alert(.presented(.confirmDelete)):
                state.loading = true
                return .run { [id = state.id] send in
                    let response = try await service.deleteArchive(id: id).value
                    if response.success == 1 {
                        await send(.deleteSuccess)
                    } else {
                        await send(.setErrorMessage(NSLocalizedString("error.archive.delete", comment: "error")))
                    }
                } catch: { [id = state.id] error, _ in
                    logger.error("failed to delete archive, id=\(id) \(error)")
                }
            case .alert:
                return .none
            case .deleteSuccess:
                state.loading = false
                return .none
            default:
                return .none
            }
        }
        .ifLet(\.$alert, action: \.alert)
    }

    struct ArchiveMetadata: Equatable {
        let title: String
        let archiveThumbnail: ArchiveThumbnail?
        let tags: String
    }
}

struct ArchiveDetailsV2: View {
    private static let sourceTag = "source"
    private static let dateTag = "date_added"

    let store: StoreOf<ArchiveDetailsFeature>

    var body: some View {
        WithViewStore(self.store, observe: { $0 }) { (viewStore: ViewStoreOf<ArchiveDetailsFeature>) in
            if viewStore.archiveMetadata != nil {
                ScrollView {
                    if viewStore.editMode == .active {
                        TextField("", text: viewStore.$title, axis: .vertical)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .textFieldStyle(.roundedBorder)
                            .padding()
                    } else {
                        Text(viewStore.archiveMetadata!.title)
                            .textFieldStyle(.roundedBorder)
                            .textSelection(.enabled)
                            .padding()
                    }
                    if let imageData = viewStore.archiveMetadata!.archiveThumbnail?.thumbnail {
                        Image(uiImage: UIImage(data: imageData)!)
                            .resizable()
                            .scaledToFit()
                            .padding()
                            .frame(width: 200, height: 250)
                    } else {
                        Image(systemName: "photo")
                            .foregroundColor(.primary)
                    }
                    if viewStore.editMode == .active {
                        TextField("", text: viewStore.$tags, axis: .vertical)
                            .textFieldStyle(.roundedBorder)
                            .textInputAutocapitalization(.never)
                            .disableAutocorrection(true)
                            .padding()
                    } else {
                        WrappingHStack(
                            models: viewStore.archiveMetadata!.tags.split(separator: ","),
                            viewGenerator: { tag in
                                parseTag(tag: String(tag))
                                    .padding()
                                    .controlSize(.mini)
                                    .foregroundColor(.white)
                                    .background(.blue)
                                    .clipShape(Capsule())
                            })
                        .padding()
                    }
                    if viewStore.editMode != .active {
                        Button(
                            role: .destructive,
                            action: { viewStore.send(.deleteButtonTapped) },
                            label: {
                                Text("archive.delete")
                            }
                        )
                        .padding()
                        .background(.red)
                        .foregroundColor(.white)
                        .clipShape(Capsule())
                        .disabled(viewStore.loading)
                    }
                }
                .toolbar {
                    ToolbarItemGroup(placement: .topBarTrailing) {
                        Menu {
                            Text("archive.category.manage")
                        } label: {
                            Image(systemName: "folder.badge.gear")
                        }
                        .disabled(viewStore.loading)
                        EditButton()
                            .disabled(viewStore.loading)
                    }
                }
                .environment(\.editMode, viewStore.$editMode)
                .alert(
                  store: self.store.scope(
                    state: \.$alert,
                    action: { .alert($0) }
                  )
                )
            } else {
                ProgressView("loading")
                    .onAppear {
                        viewStore.send(.loadMetadata)
                    }
            }

        }
    }

    private func parseTag(tag: String) -> some View {
        let tagPair = tag.split(separator: ":", maxSplits: 1)

        let tagName = tagPair[0].trimmingCharacters(in: .whitespacesAndNewlines)
        let tagValue = tagPair.count == 2 ? tagPair[1].trimmingCharacters(in: .whitespacesAndNewlines) : ""
        if tagName == ArchiveDetailsV2.sourceTag {
            let urlString = tagValue.hasPrefix("http") ? tagValue : "https://\(tagValue)"
            return AnyView(Link(destination: URL(string: urlString)!) {
                Text(tag)
            })
        }
        let processedTag: String
        if tagName == ArchiveDetailsV2.dateTag {
            let date = Date(timeIntervalSince1970: TimeInterval(tagValue) ?? 0)
            processedTag = "\(ArchiveDetailsV2.dateTag): \(date.formatted(date: .abbreviated, time: .omitted))"
        } else {
            processedTag = tag
        }
        let normalizedTag = String(tag.trimmingCharacters(in: .whitespacesAndNewlines))
        return AnyView(NavigationLink(
            state: AppFeature.Path.State.search(
                SearchFeature.State.init(
                    keyword: normalizedTag, archiveList: ArchiveListFeature.State(
                        filter: SearchFilter(category: nil, filter: normalizedTag),
                        loadOnAppear: true
                    )
                )
            )
        ) {
            Text(processedTag)
        })
    }
}
