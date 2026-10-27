import UIKit
import Observation

@MainActor
@Observable
final class NavigationHelper {
    weak var navigationController: UINavigationController?

    func push(_ viewController: UIViewController) {
        navigationController?.pushViewController(viewController, animated: true)
    }

    func pop() {
        navigationController?.popViewController(animated: true)
    }
}
