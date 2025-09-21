import SwiftUI
import UIKit
import Observation

@Observable
final class NavigationHelper {
    weak var navigationController: UINavigationController?

    func push<Content: View>(_ view: Content) {
        let hostingVC = UIHostingController(rootView: view)
        navigationController?.pushViewController(hostingVC, animated: true)
    }

    func push(_ viewController: UIViewController) {
        navigationController?.pushViewController(viewController, animated: true)
    }

    func pop() {
        navigationController?.popViewController(animated: true)
    }
}
