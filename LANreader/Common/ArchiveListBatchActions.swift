import ComposableArchitecture
import Foundation
import Logging

extension ArchiveListFeature {
    func handleConfirmRemoveFromCategory(state: inout State) -> EffectOf<Self> {
        guard state.canStartBatchAction,
              let categoryId = state.currentStaticCategoryId else { return .none }
        state.loading = true
        state.batchActionInProgress = true
        let selected = state.selected
        return .run { send in
            var successIds: Set<String> = .init()
            var errorIds: Set<String> = .init()

            for archiveId in selected.sorted() {
                do {
                    let response = try await service.removeArchiveFromCategory(
                        categoryId: categoryId, archiveId: archiveId
                    ).value
                    if response.success == 1 {
                        successIds.insert(archiveId)
                    } else {
                        errorIds.insert(archiveId)
                    }
                } catch {
                    logger.error(
                        """
                        failed to remove archive from category.
                        categoryId=\(categoryId), archiveId=\(archiveId) \(error)
                        """
                    )
                    errorIds.insert(archiveId)
                }
            }
            await send(.removeFromCategoryFinished(categoryId, successIds, !errorIds.isEmpty))
        }
    }

    func handleRemoveFromCategoryFinished(
        categoryId: String,
        archiveIds: Set<String>,
        hadErrors: Bool,
        state: inout State
    ) -> EffectOf<Self> {
        state.$categoryItems.withLock {
            $0[id: categoryId]?.archives.removeAll(where: archiveIds.contains)
        }
        archiveIds.forEach { id in
            state.selected.remove(id)
            state.archivesToDisplay.remove(id: id)
            state.archives.remove(id: id)
        }
        state.loading = false
        state.batchActionInProgress = false
        if hadErrors {
            state.errorMessage = String(localized: "archive.selected.category.remove.error")
        } else {
            state.successMessage = String(localized: "archive.selected.category.remove.success")
        }
        return reloadPageAfterRemoval(state: &state, removedCount: archiveIds.count)
    }

    func handleConfirmDelete(state: inout State) -> EffectOf<Self> {
        guard state.canStartBatchAction else { return .none }
        state.loading = true
        state.batchActionInProgress = true
        return deleteSelected(state)
    }

    func handleDeleteFinished(
        archiveIds: Set<String>,
        hadErrors: Bool,
        state: inout State
    ) -> EffectOf<Self> {
        state.batchActionInProgress = false
        archiveIds.forEach { id in
            state.selected.remove(id)
            state.archivesToDisplay.remove(id: id)
            state.archives.remove(id: id)
            state.$archiveItems.withLock { _ = $0.remove(id: id) }
        }
        state.$categoryItems.withLock { categories in
            for index in categories.indices {
                categories[index].archives.removeAll(where: archiveIds.contains)
            }
        }
        state.loading = false
        if hadErrors {
            state.errorMessage = String(localized: "archive.selected.delete.error")
        } else {
            state.successMessage = String(localized: "archive.selected.delete.success")
        }
        if archiveIds.contains(where: \.isTankoubonArchiveId) {
            state.preserveSelectionOnNextPopulate = true
            let page = state.paginationActive
                ? PaginationPositioning.clampedPage(state.currentPage, pageCount: state.pageCount)
                : 0
            return loadArchives(state: &state, page: page)
        }
        return reloadPageAfterRemoval(state: &state, removedCount: archiveIds.count)
    }

    func handleAddArchivesToCategory(_ categoryId: String, state: inout State) -> EffectOf<Self> {
        guard state.canStartBatchAction,
              state.categoryItems[id: categoryId] != nil else { return .none }
        state.loading = true
        state.batchActionInProgress = true
        let selected = state.selected
        return .run { send in
            var successIds: Set<String> = .init()
            var errorIds: Set<String> = .init()

            for archiveId in selected.sorted() {
                do {
                    let response = try await service.addArchiveToCategory(
                        categoryId: categoryId, archiveId: archiveId
                    ).value
                    if response.success == 1 {
                        successIds.insert(archiveId)
                    } else {
                        errorIds.insert(archiveId)
                    }
                } catch {
                    logger.error(
                        """
                        failed to add archive to category.
                        categoryId=\(categoryId), archiveId=\(archiveId) \(error)
                        """
                    )
                    errorIds.insert(archiveId)
                }
            }
            await send(.addArchivesToCategoryFinished(categoryId, successIds, !errorIds.isEmpty))
        }
    }

    func handleAddArchivesToCategoryFinished(
        categoryId: String,
        archiveIds: Set<String>,
        hadErrors: Bool,
        state: inout State
    ) -> EffectOf<Self> {
        state.$categoryItems.withLock {
            for archiveId in archiveIds where $0[id: categoryId]?.archives.contains(archiveId) == false {
                $0[id: categoryId]?.archives.append(archiveId)
            }
        }
        archiveIds.forEach { state.selected.remove($0) }
        state.loading = false
        state.batchActionInProgress = false
        if hadErrors {
            state.errorMessage = String(localized: "archive.selected.category.add.error")
        } else {
            state.successMessage = String(localized: "archive.selected.category.add.success")
        }
        return .none
    }

    func handleCreateTankoubon(_ rawName: String, state: inout State) -> EffectOf<Self> {
        guard state.canStartBatchAction else { return .none }
        let name = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else {
            state.errorMessage = String(localized: "archive.selected.tankoubon.name.required")
            return .none
        }
        guard !state.selected.contains(where: \.isTankoubonArchiveId) else {
            state.errorMessage = String(localized: "archive.selected.tankoubon.nested.error")
            return .none
        }
        state.loading = true
        state.batchActionInProgress = true
        let archives = Array(state.selected)
        return .run { send in
            var createdTankoubon = false
            do {
                let created = try await service.createTankoubon(name: name).value
                guard created.success == 1, let id = created.tankoubonId, !id.isEmpty else {
                    await send(.createTankoubonFailed(String(localized: "archive.selected.tankoubon.create.error")))
                    return
                }
                createdTankoubon = true
                let updated = try await service.updateTankoubon(id: id, archives: archives).value
                guard updated.success == 1 else {
                    await send(.createTankoubonFailed(String(localized: "archive.selected.tankoubon.contents.error")))
                    return
                }
                await send(.createTankoubonSucceeded)
            } catch {
                logger.error("failed to create or populate Tankoubon. \(error)")
                let message = createdTankoubon
                    ? String(localized: "archive.selected.tankoubon.contents.error")
                    : String(localized: "archive.selected.tankoubon.create.error")
                await send(.createTankoubonFailed(message))
            }
        }
    }

    func handleCreateTankoubonSucceeded(state: inout State) -> EffectOf<Self> {
        state.loading = false
        state.batchActionInProgress = false
        state.successMessage = String(localized: "archive.selected.tankoubon.create.success")
        return .send(.reloadFromFirstPage)
    }

    func handleCreateTankoubonFailed(_ message: String, state: inout State) -> EffectOf<Self> {
        state.loading = false
        state.batchActionInProgress = false
        state.errorMessage = message
        return .none
    }

    private func deleteSelected(_ state: State) -> EffectOf<Self> {
        return .run { [state] send in
            var successIds: Set<String> = .init()
            var errorIds: Set<String> = .init()

            for archiveId in state.selected.sorted() {
                do {
                    let request = if archiveId.isTankoubonArchiveId {
                        await service.deleteTankoubon(id: archiveId)
                    } else {
                        await service.deleteArchive(id: archiveId)
                    }
                    let response = try await request.value
                    if response.success == 1 {
                        successIds.insert(archiveId)
                    } else {
                        errorIds.insert(archiveId)
                    }
                } catch {
                    logger.error("failed to delete archive id=\(archiveId) \(error)")
                    errorIds.insert(archiveId)
                }
            }

            await send(.deleteFinished(successIds, !errorIds.isEmpty))
        }
    }
}
