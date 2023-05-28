//
// Created on 3/10/20.
//

import Foundation
import SwiftUI
import Logging

enum PageAction {
    case startExtractArchive
    case finishExtractArchive
    case storeExtractedArchive(id: String, pages: [String])

    case error(error: ErrorCode)
    case resetState
}

// MARK: thunk actions

private let logger = Logger(label: "PageAction")
private let database = AppDatabase.shared
private let lanraragiService = LANraragiService.shared

func extractArchive(id: String) async -> ThunkAction<AppAction, AppState> {
    { dispatch, _ in
        dispatch(.page(action: .startExtractArchive))
        do {
            let extractResponse = try await lanraragiService.extractArchive(id: id).value
            if extractResponse.pages.isEmpty {
                logger.error("server returned empty pages. id=\(id)")
                dispatch(.page(action: .error(error: .emptyPageError)))
            } else {
                var allPages = [String]()
                extractResponse.pages.forEach { page in
                    let normalizedPage = String(page.dropFirst(2))
                    allPages.append(normalizedPage)
                }
                dispatch(.page(action: .storeExtractedArchive(id: id, pages: allPages)))
            }
        } catch {
            logger.error("failed to extract archive page. id=\(id) \(error)")
            dispatch(.page(action: .error(error: .archiveExtractError)))
        }
        dispatch(.page(action: .finishExtractArchive))
    }
}
