import ComposableArchitecture
import Foundation
import Logging

extension ArchiveListFeature {
    func handleCacheSelected(state: inout State) -> EffectOf<Self> {
        guard state.canStartBatchAction else { return .none }
        let ids = state.selected.sorted()
        let previous = state.cachingArchiveIds
        let effects = ids.map { cacheArchive(state: &state, id: $0) }
        state.batchCachingArchiveIds.formUnion(state.cachingArchiveIds.subtracting(previous))
        state.selected.formIntersection(state.batchCachingArchiveIds)
        return .merge(effects)
    }

    func cacheArchive(state: inout State, id: String) -> EffectOf<Self> {
        guard !state.cachingArchiveIds.contains(id),
              let archive = state.archives[id: id]?.archive else {
            return .none
        }
        if (try? database.existCache(id)) == true {
            return .none
        }
        state.cachingArchiveIds.insert(id)
        return .run(priority: .utility) { send in
            let extraction = try await service.extractArchiveForReading(id: id)
            guard !extraction.pages.isEmpty else {
                await send(.cacheArchiveFailed(id, String(localized: "error.page.empty")))
                return
            }

            try await service.saveAndCacheArchive(
                archive,
                pages: extraction.pages,
                toc: extraction.tankoubonDetails?.toc,
                database: database
            )
            await send(.cacheArchiveFinished(id))
        } catch: { error, send in
            logger.error("failed to cache archive. id=\(id) \(error)")
            await send(.cacheArchiveFailed(id, error.localizedDescription))
        }
    }

    func finishCaching(state: inout State, id: String, succeeded: Bool, error: String? = nil) {
        guard state.batchCachingArchiveIds.remove(id) != nil else {
            if succeeded { state.successMessage = String(localized: "archive.cache.added") }
            if let error { state.errorMessage = error }
            return
        }
        if let error {
            state.batchCacheErrors.insert(error)
        }
        if succeeded { state.selected.remove(id) }
        state.batchCacheHadSuccess = state.batchCacheHadSuccess || succeeded
        guard state.batchCachingArchiveIds.isEmpty else { return }
        if !state.batchCacheErrors.isEmpty {
            state.errorMessage = state.batchCacheErrors.sorted().joined(separator: "\n")
        } else if state.batchCacheHadSuccess {
            state.successMessage = String(localized: "archive.cache.added")
        }
        state.batchCacheErrors.removeAll()
        state.batchCacheHadSuccess = false
    }
}
