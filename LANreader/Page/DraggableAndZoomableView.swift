import SwiftUI

// Handle dragging
struct DraggableAndZoomableView: ViewModifier {

    private var contentSize: CGSize

    @GestureState private var scaleState: CGFloat = 1
    @GestureState private var offsetState = CGSize.zero

    @State private var offset = CGSize.zero
    @State private var scale: CGFloat = 1

    func resetStatus() {
        self.offset = CGSize.zero
        self.scale = 1
    }

    init(contentSize: CGSize) {
        self.contentSize = contentSize
        resetStatus()
    }

    var zoomGesture: some Gesture {
        MagnificationGesture()
                .updating($scaleState) { currentState, gestureState, _ in
                    gestureState = currentState
                }
                .onEnded { value in
                    if scale * value <= 1 {
                        resetStatus()
                    } else {
                        scale *= value
                    }
                }
    }

    var dragGesture: some Gesture {
        DragGesture(minimumDistance: minDistance())
                .updating($offsetState) { currentState, gestureState, _ in
                    if scale > 1.0 {
                        gestureState = currentState.translation
                    }
                }
                .onEnded { value in
                    if scale > 1.0 {
                        offset.height = calEdge(offset: offset.height + value.translation.height, isWidth: false)
                        offset.width = calEdge(offset: offset.width + value.translation.width, isWidth: true)
                    }
                }

    }

    var doubleTapGesture: some Gesture {
        TapGesture(count: 2).onEnded { _ in
            resetStatus()
        }
    }

    func body(content: Content) -> some View {
        content
                .scaleEffect(self.scale * scaleState)
                .offset(x: calEdge(offset: offset.width + offsetState.width, isWidth: true),
                        y: calEdge(offset: offset.height + offsetState.height, isWidth: false))
                .gesture(SimultaneousGesture(zoomGesture, dragGesture))
                .simultaneousGesture(doubleTapGesture)
    }

    private func minDistance() -> CGFloat {
        if scale > 1.0 {
            return CGFloat.zero
        } else {
            return CGFloat.infinity
        }
    }

    private func calEdge(offset: CGFloat, isWidth: Bool) -> CGFloat {
        let edge: CGFloat
        if isWidth {
            edge = (contentSize.width / 2) * (scale * scaleState - 1)
        } else {
            edge = (contentSize.height / 2) * (scale * scaleState - 1)
        }
        if offset > edge {
            return edge
        } else if offset < -edge {
            return -edge
        } else {
            return offset
        }
    }
}

// Wrap `draggable()` in a View extension to have a clean call site
extension View {
    func draggableAndZoomable(contentSize: CGSize) -> some View {
        modifier(DraggableAndZoomableView(contentSize: contentSize))
    }
}
