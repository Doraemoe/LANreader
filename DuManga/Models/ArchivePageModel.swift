//
// Created on 16/9/20.
//

import Foundation
import Combine
import SwiftUI
import Logging

enum InternalPageSplitState: String, CaseIterable {
    case off
    case first
    case last
}

enum PageFlipAction: String, CaseIterable {
    case next
    case previous
    case jump
}

class ArchivePageModel: ObservableObject {
    private static let logger = Logger(label: "ArchivePageModel")

    @Published var currentIndex: Double = 0.0
    @Published var controlUiHidden = true
    @Published var isCurrentSplittingPage = InternalPageSplitState.off
    @Published var leftHalfPage = Image("placeholder")
    @Published var rightHalfPage = Image("placeholder")
    @Published var currentImage = Image("placeholder")

    @Published private(set) var loading = false
    @Published private(set) var archiveItems = [String: ArchiveItem]()
    @Published private(set) var archivePages = [String: [String]]()
    @Published private(set) var errorCode: ErrorCode?

    private let service = LANraragiService.shared

    private var cancellables: Set<AnyCancellable> = []

    func load(state: AppState, progress: Int) {
        state.page.$loading.receive(on: DispatchQueue.main)
                .assign(to: \.loading, on: self)
                .store(in: &cancellables)

        state.archive.$archiveItems.receive(on: DispatchQueue.main)
                .assign(to: \.archiveItems, on: self)
                .store(in: &cancellables)

        state.page.$archivePages.receive(on: DispatchQueue.main)
                .assign(to: \.archivePages, on: self)
                .store(in: &cancellables)

        state.page.$errorCode.receive(on: DispatchQueue.main)
                .assign(to: \.errorCode, on: self)
                .store(in: &cancellables)
        currentIndex = Double(progress)
    }

    func unload() {
        cancellables.forEach({ $0.cancel() })
    }

    func verifyArchiveExists(id: String) -> Bool {
        archiveItems[id] != nil
    }

    func loadPage(page: String,
                  split: Bool,
                  priorityLeft: Bool,
                  action: PageFlipAction,
                  dispatchError: @escaping (ErrorCode) -> Void) {
        service.fetchArchivePage(page: page)
                .map {
                    if split && $0.size.width / $0.size.height > 1.2 {
                        let success = self.cropAndSetInternalImage(image: $0)
                        if success {
                            return self.jumpToInternalPage(priorityLeft: priorityLeft, action: action)
                        } else {
                            return Image("placeholder")
                        }
                    } else {
                        return Image(uiImage: $0)
                    }
                }
                .catch { error -> Just<Image> in
                    ArchivePageModel.logger.error("error load image: \(error)")
                    dispatchError(.archiveFetchPageError)
                    return Just(Image("placeholder"))
                }
                .receive(on: DispatchQueue.main)
                .assign(to: \.currentImage, on: self)
                .store(in: &cancellables)
    }

    func jumpToInternalPage(priorityLeft: Bool, action: PageFlipAction) -> Image {
        switch action {
        case .next, .jump:
            self.isCurrentSplittingPage = .first
            if priorityLeft {
                return self.leftHalfPage
            } else {
                return self.rightHalfPage
            }
        case .previous:
            self.isCurrentSplittingPage = .last
            if priorityLeft {
                return self.rightHalfPage
            } else {
                return self.leftHalfPage
            }
        }
    }

    func cropAndSetInternalImage(image: UIImage) -> Bool {
        if let cgImage = image.cgImage {
            if let leftHalf = cgImage.cropping(
                    to: CGRect(x: 0, y: 0, width: cgImage.width / 2, height: cgImage.height)) {
                self.leftHalfPage = Image(uiImage: UIImage(cgImage: leftHalf))
            } else {
                return false
            }
            if let rightHalf = cgImage.cropping(
                    to: CGRect(x: cgImage.width / 2, y: 0, width: cgImage.width, height: cgImage.height)) {
                self.rightHalfPage = Image(uiImage: UIImage(cgImage: rightHalf))
            } else {
                return false
            }
        } else {
            return false
        }
        return true
    }

    func setCurrentPageToLeft() {
        self.currentImage = self.leftHalfPage
    }

    func setCurrentPageToRight() {
        self.currentImage = self.rightHalfPage
    }

    func setCurrentPageToImage(image: Image) {
        self.currentImage = image
    }

    func clearNewFlag(id: String) {
        self.service.clearNewFlag(id: id)
                .replaceError(with: "NOOP")
                .sink(receiveValue: { _ in
                    // NOOP
                })
                .store(in: &cancellables)
    }
}
