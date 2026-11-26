import ComposableArchitecture
import SwiftUI

struct ArchiveReader: View {
    @Bindable var store: StoreOf<ArchiveReaderFeature>

    var body: some View {
        let flip = store.readDirection == ReadDirection.rightLeft.rawValue
        GeometryReader { geometry in
            Group {
                if store.readDirection == ReadDirection.upDown.rawValue {
                    UIPageCollection(store: store)
                } else {
                    UIPageCollection(store: store)
                        .environment(\.layoutDirection, flip ? .rightToLeft : .leftToRight)
                }
            }
            .overlay(alignment: .bottom) {
                if !store.controlUiHidden {
                    ReaderBottomToolbar(store: store, readerSize: geometry.size)
                        .environment(\.layoutDirection, flip ? .rightToLeft : .leftToRight)
                }
            }
            .overlay {
                if store.extracting {
                    LoadingView(geometry: geometry)
                }
            }
        }
        .alert(
            $store.scope(\.$alert, action: \.alert)
        )
        .alert(
            store.chapterEditingTarget == nil
                ? "archive.reader.chapter.add"
                : "archive.reader.chapter.edit.title",
            isPresented: Binding(
                get: { store.chapterCreationTarget != nil || store.chapterEditingTarget != nil },
                set: { isPresented in
                    if !isPresented {
                        store.send(.cancelChapterMutation)
                    }
                }
            )
        ) {
            TextField(
                "archive.reader.chapter.title.placeholder",
                text: $store.chapterTitle
            )
            if store.chapterEditingTarget != nil {
                Button("delete", role: .destructive) {
                    store.send(.confirmChapterDeletion)
                }
            }
            Button("cancel", role: .cancel) {
                store.send(.cancelChapterMutation)
            }
            Button("save") {
                store.send(.confirmChapterMutation)
            }
            .disabled(store.chapterTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .alert(
            "archive.reader.stamp.add.title",
            isPresented: Binding(
                get: { store.stampCreationTarget != nil },
                set: { isPresented in
                    if !isPresented, store.stampCreationTarget != nil {
                        store.send(.cancelStampCreation)
                    }
                }
            )
        ) {
            TextField(
                "archive.reader.stamp.text.placeholder",
                text: Binding(
                    get: { store.stampComment },
                    set: { store.send(.stampCommentChanged($0)) }
                )
            )
            Button("cancel", role: .cancel) {
                store.send(.cancelStampCreation)
            }
            Button("save") {
                store.send(.confirmStampCreation)
            }
            .disabled(store.stampComment.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .alert(
            "archive.reader.stamp.edit.title",
            isPresented: Binding(
                get: { store.stampEditingTarget != nil },
                set: { isPresented in
                    if !isPresented, store.stampEditingTarget != nil {
                        store.send(.cancelStampEditing)
                    }
                }
            )
        ) {
            TextField(
                "archive.reader.stamp.text.placeholder",
                text: Binding(
                    get: { store.stampEditText },
                    set: { store.send(.stampEditTextChanged($0)) }
                )
            )
            Button("delete", role: .destructive) {
                store.send(.confirmStampDeletion)
            }
            Button("cancel", role: .cancel) {
                store.send(.cancelStampEditing)
            }
            Button("save") {
                store.send(.confirmStampEditing)
            }
            .disabled(store.stampEditText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .overlay(content: {
            store.showAutoPageConfig ? AutomaticPageConfig(
                store: store.scope(\.autoPage, action: \.autoPage)
            ) : nil
        })
        .task {
            if store.pages.isEmpty {
                if store.cached {
                    store.send(.loadCached)
                } else {
                    store.send(.extractArchive)
                }
            }
            guard let currentArchive = store.allArchives[id: store.currentArchiveId] else { return }
            if currentArchive.wrappedValue.extension == "rar" || currentArchive.wrappedValue.extension == "cbr" {
                showNotificationBanner(
                    title: String(localized: "warning"),
                    subtitle: String(localized: "warning.file.type"),
                    style: .warning
                )
            }
        }
        .onChange(of: store.errorMessage) {
            if !store.errorMessage.isEmpty {
                showNotificationBanner(
                    title: String(localized: "error"),
                    subtitle: store.errorMessage,
                    style: .danger
                )
                store.send(.toggleControlUi(false))
                store.send(.setError(""))
            }
        }
        .onChange(of: store.successMessage) {
            if !store.successMessage.isEmpty {
                showNotificationBanner(
                    title: String(localized: "success"),
                    subtitle: store.successMessage,
                    style: .success
                )
                store.send(.setSuccess(""))
            }
        }
    }
}
