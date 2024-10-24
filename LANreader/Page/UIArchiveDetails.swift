import UIKit
import SwiftUI
import ComposableArchitecture

public struct UIArchiveDetails: UIViewControllerRepresentable {
    let store: StoreOf<ArchiveDetailsFeature>

    public init(store: StoreOf<ArchiveDetailsFeature>) {
        self.store = store
    }

    public func makeUIViewController(context: Context) -> UIViewController {
        UIArchiveDetailsController(store: store)
    }

    public func updateUIViewController(
        _ uiViewController: UIViewController,
        context: Context
    ) {
        // Nothing to do
    }
}

class UIArchiveDetailsController: UIViewController {
    let store: StoreOf<ArchiveDetailsFeature>

    init(store: StoreOf<ArchiveDetailsFeature>) {
        self.store = store
        super.init()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}
