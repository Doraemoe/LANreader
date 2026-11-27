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
            store.chapter.editingTarget == nil
                ? "archive.reader.chapter.add"
                : "archive.reader.chapter.edit.title",
            isPresented: Binding(
                get: { store.chapter.creationTarget != nil || store.chapter.editingTarget != nil },
                set: { isPresented in
                    if !isPresented {
                        store.send(.chapter(.cancelMutation))
                    }
                }
            )
        ) {
            TextField(
                "archive.reader.chapter.title.placeholder",
                text: Binding(
                    get: { store.chapter.title },
                    set: { store.send(.chapter(.titleChanged($0))) }
                )
            )
            if store.chapter.editingTarget != nil {
                Button("delete", role: .destructive) {
                    store.send(.chapter(.confirmDeletion))
                }
            }
            Button("cancel", role: .cancel) {
                store.send(.chapter(.cancelMutation))
            }
            Button("save") {
                store.send(.chapter(.confirmMutation))
            }
            .disabled(store.chapter.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .alert(
            "archive.reader.stamp.add.title",
            isPresented: Binding(
                get: { store.stamp.creationTarget != nil },
                set: { isPresented in
                    if !isPresented, store.stamp.creationTarget != nil {
                        store.send(.stamp(.cancelCreation))
                    }
                }
            )
        ) {
            TextField(
                "archive.reader.stamp.text.placeholder",
                text: Binding(
                    get: { store.stamp.comment },
                    set: { store.send(.stamp(.commentChanged($0))) }
                )
            )
            Button("cancel", role: .cancel) {
                store.send(.stamp(.cancelCreation))
            }
            Button("save") {
                store.send(.stamp(.confirmCreation))
            }
            .disabled(store.stamp.comment.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .alert(
            "archive.reader.stamp.edit.title",
            isPresented: Binding(
                get: { store.stamp.editingTarget != nil },
                set: { isPresented in
                    if !isPresented, store.stamp.editingTarget != nil {
                        store.send(.stamp(.cancelEditing))
                    }
                }
            )
        ) {
            TextField(
                "archive.reader.stamp.text.placeholder",
                text: Binding(
                    get: { store.stamp.editText },
                    set: { store.send(.stamp(.editTextChanged($0))) }
                )
            )
            Button("delete", role: .destructive) {
                store.send(.stamp(.confirmDeletion))
            }
            Button("cancel", role: .cancel) {
                store.send(.stamp(.cancelEditing))
            }
            Button("save") {
                store.send(.stamp(.confirmEditing))
            }
            .disabled(store.stamp.editText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
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
