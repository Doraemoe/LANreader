import ComposableArchitecture

extension ArchiveReaderFeature {
    func handleStampDelegate(
        _ action: ReaderStampFeature.Action.Delegate,
        state: inout State
    ) -> Effect<Action> {
        switch action {
        case .unsupportedServerResolved:
            for pageId in state.pages.ids {
                state.pages[id: pageId]?.stampsLoading = false
                state.pages[id: pageId]?.stampsLoaded = true
            }
            return .none
        case let .created(target, stamp, refreshedStamps):
            return applyCreatedStamp(target: target, stamp: stamp, refreshedStamps: refreshedStamps, state: &state)
        case let .updated(target, content):
            applyUpdatedStamp(target: target, content: content, state: &state)
            return .none
        case let .deleted(target):
            applyDeletedStamp(target: target, state: &state)
            return .none
        case let .errorOccurred(message):
            state.errorMessage = message
            return .none
        }
    }

    private func applyCreatedStamp(
        target: StampCreationTarget,
        stamp: ArchiveStamp,
        refreshedStamps: [ArchiveStamp]?,
        state: inout State
    ) -> Effect<Action> {
        let matchingPageIds = state.pages.compactMap { page in
            page.sourceArchiveId == target.sourceArchiveId
                && page.sourcePageNumber == target.sourcePageNumber
                ? page.id
                : nil
        }
        guard !matchingPageIds.isEmpty else { return .none }
        for pageId in matchingPageIds {
            if let refreshedStamps {
                state.pages[id: pageId]?.stamps = refreshedStamps
                state.pages[id: pageId]?.stampsLoaded = true
                state.pages[id: pageId]?.stampsLoading = false
            } else {
                if state.pages[id: pageId]?.stamps.contains(stamp) == false {
                    state.pages[id: pageId]?.stamps.append(stamp)
                }
                state.pages[id: pageId]?.stampsLoaded = false
                state.pages[id: pageId]?.stampsLoading = false
            }
        }
        state.$showStamps.withLock { $0 = true }
        guard refreshedStamps == nil else { return .none }
        return .merge(matchingPageIds.map { pageId in
            .send(.page(.element(id: pageId, action: .loadStamps)))
        })
    }

    private func applyUpdatedStamp(
        target: StampEditingTarget,
        content: String,
        state: inout State
    ) {
        for pageId in state.pages.ids {
            guard let page = state.pages[id: pageId],
                  page.sourceArchiveId == target.sourceArchiveId,
                  page.sourcePageNumber == target.sourcePageNumber,
                  let index = page.stamps.firstIndex(where: { $0.id == target.stampId }) else {
                continue
            }
            let stamp = page.stamps[index]
            state.pages[id: pageId]?.stamps[index] = ArchiveStamp(
                id: stamp.id,
                position: stamp.position,
                content: content
            )
        }
    }

    private func applyDeletedStamp(
        target: StampEditingTarget,
        state: inout State
    ) {
        for pageId in state.pages.ids {
            guard let page = state.pages[id: pageId],
                  page.sourceArchiveId == target.sourceArchiveId,
                  page.sourcePageNumber == target.sourcePageNumber else {
                continue
            }
            state.pages[id: pageId]?.stamps.removeAll { $0.id == target.stampId }
        }
    }

    func handleChapterDelegate(
        _ action: ReaderChapterFeature.Action.Delegate,
        state: inout State
    ) -> Effect<Action> {
        switch action {
        case let .jumpRequested(pageIndex):
            return .send(.requestJump(pageIndex, source: .chapter))
        case let .saved(target, title):
            applySavedChapter(target: target, title: title, state: &state)
            return .none
        case let .deleted(target):
            applyDeletedChapter(target: target, state: &state)
            return .none
        case let .errorOccurred(message):
            state.errorMessage = message
            return .none
        }
    }

    private func applySavedChapter(
        target: ChapterMutationTarget,
        title: String,
        state: inout State
    ) {
        guard let archive = state.allArchives[id: target.readerArchiveId] else { return }
        let chapters = ReaderChapterFeature.chaptersBySaving(
            title,
            at: target.readerPageNumber,
            in: archive.wrappedValue.toc ?? []
        )
        archive.withLock { $0.toc = chapters }
        if state.currentTankoubonDetails?.id == target.readerArchiveId {
            state.currentTankoubonDetails?.toc = chapters
            state.currentTankoubonDetails?.automaticChapterPages.remove(target.readerPageNumber)
        }
    }

    private func applyDeletedChapter(
        target: ChapterMutationTarget,
        state: inout State
    ) {
        guard let archive = state.allArchives[id: target.readerArchiveId] else { return }
        let result = ReaderChapterFeature.applyChapterDeletion(
            at: target.readerPageNumber,
            chapters: archive.wrappedValue.toc ?? [],
            defaultChapters: state.currentTankoubonDetails?.defaultChapters ?? []
        )
        if state.currentTankoubonDetails?.id == target.readerArchiveId {
            if let restoredPage = result.restoredDefaultPage {
                state.currentTankoubonDetails?.automaticChapterPages.insert(restoredPage)
            }
            state.currentTankoubonDetails?.toc = result.chapters.isEmpty ? nil : result.chapters
        }
        archive.withLock { $0.toc = result.chapters.isEmpty ? nil : result.chapters }
    }
}
