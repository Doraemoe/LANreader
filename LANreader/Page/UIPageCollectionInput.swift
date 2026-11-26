import UIKit

extension UIPageCollectionController: UIGestureRecognizerDelegate {
    enum TapRegion {
        case left
        case middle
        case right
    }

    func setupGesture() {
        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(handleTap(_:)))
        tapGesture.numberOfTapsRequired = 1
        collectionView.addGestureRecognizer(tapGesture)
        tapGesture.delegate = self
    }

    @discardableResult
    func handleKeyPress(_ keyCode: UIKeyboardHIDUsage) -> Bool {
        switch keyCode {
        case .keyboardLeftArrow:
            handlePageControl(store.tapRight, source: .keyboard)
            return true
        case .keyboardRightArrow:
            handlePageControl(store.tapLeft, source: .keyboard)
            return true
        default:
            return false
        }
    }

    @objc private func handleTap(_ gesture: UITapGestureRecognizer) {
        let width = view.bounds.width
        let locationInView = gesture.location(in: view)
        // Clamp just in case (e.g. during interactive transitions)
        let xAxis = max(0, min(width, locationInView.x))

        let region: TapRegion
        switch xAxis {
        case ..<(width / 3):
            region = .left
        case (width / 3)..<(2 * width / 3):
            region = .middle
        default:
            region = .right
        }

        // Handle the tap based on region
        handleTapInRegion(region)
    }

    private func handleTapInRegion(_ region: TapRegion) {
        // Handle tap in region but not on any cell
        if store.readDirection != ReadDirection.upDown.rawValue {
            switch region {
            case .left:
                handlePageControl(store.tapLeft, source: .tap)
            case .middle:
                handlePageControl(store.tapMiddle, source: .tap)
            case .right:
                handlePageControl(store.tapRight, source: .tap)
            }
        } else {
            store.send(.toggleControlUi(nil))
        }
    }

    func handlePageControl(_ action: String, source: ReaderNavigationSource) {
        switch action {
        case PageControl.next.rawValue:
            store.send(.navigate(.next, source: source))
        case PageControl.previous.rawValue:
            store.send(.navigate(.previous, source: source))
        case PageControl.navigation.rawValue:
            store.send(.toggleControlUi(nil))
        default:
            break
        }
    }

    func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
    ) -> Bool {
        if store.readDirection == ReadDirection.upDown.rawValue {
            if collectionView.isDragging || collectionView.isDecelerating {
                return false
            }
        } else {
            if let innerScrollView = collectionView.subviews.first(
                where: { $0 is UIScrollView && $0 != collectionView }
            ) as? UIScrollView {
                // Only allow the tap if the scroll view is not currently dragging.
                return innerScrollView.panGestureRecognizer.state != .began &&
                    innerScrollView.panGestureRecognizer.state != .changed
            }
        }
        return true
    }
}
