import ComposableArchitecture
import SwiftUI
import UIKit

struct ReaderBottomToolbar: View {
    let store: StoreOf<ArchiveReaderFeature>
    let readerSize: CGSize

    var body: some View {
        if !store.pages.isEmpty {
            let isRightToLeft = store.resolvedReadDirection == .rightLeft
            let bubbleLayout = ReaderPageLayout.sliderPreviewBubbleLayout(readerSize: readerSize)
            let sliderHorizontalPadding = ReaderToolbarMetrics.sliderHorizontalPadding
            let sliderDisplayIndex = store.sliderPreview.draftIndex ?? store.currentPageIndex
            let sliderDisplayValue = Double(sliderDisplayIndex)
            let displayIndex = ReaderPositioning.clampedPageIndex(
                sliderDisplayIndex,
                pageCount: store.pages.count
            )
            let displayPageNumber = store.pages[displayIndex].pageNumber
            let sliderMaxIndex = max(store.pages.count - 1, 1)
            let sliderContext = ReaderSliderContext(
                displayValue: sliderDisplayValue,
                maxIndex: sliderMaxIndex,
                horizontalPadding: sliderHorizontalPadding,
                isRightToLeft: isRightToLeft
            )

            VStack(spacing: ReaderToolbarMetrics.previewBottomSpacing) {
                if store.sliderPreview.previewVisible {
                    sliderPreviewRow(
                        displayIndex: displayIndex,
                        sliderContext: sliderContext,
                        bubbleLayout: bubbleLayout,
                        showsChapterMenu: store.shouldShowChapterMenu
                    )
                }

                readerControlPanel(
                    displayPageNumber: displayPageNumber,
                    sliderContext: sliderContext
                )
            }
            .frame(maxWidth: ReaderToolbarMetrics.maxPanelWidth)
            .padding(.horizontal, ReaderToolbarMetrics.outerHorizontalPadding)
            .padding(.bottom, ReaderToolbarMetrics.bottomPadding)
            .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }

    private func sliderPreviewRow(
        displayIndex: Int,
        sliderContext: ReaderSliderContext,
        bubbleLayout: ReaderPageLayout.SliderPreviewBubbleLayout,
        showsChapterMenu: Bool
    ) -> some View {
        GeometryReader { geometry in
            let chapterMenuInset = showsChapterMenu ? ReaderToolbarMetrics.chapterMenuInset : 0
            let bubbleLeadingX = SliderPreviewPositioning.bubbleLeadingX(
                pageIndex: displayIndex,
                pageCount: store.pages.count,
                track: SliderPreviewTrackGeometry(
                    rowWidth: geometry.size.width,
                    sliderHorizontalPadding: sliderContext.horizontalPadding,
                    bubbleWidth: bubbleLayout.width,
                    leadingInset: sliderContext.isRightToLeft ? 0 : chapterMenuInset,
                    trailingInset: sliderContext.isRightToLeft ? chapterMenuInset : 0
                ),
                isRightToLeft: sliderContext.isRightToLeft
            )

            SliderPreviewBubble(
                imageURL: store.sliderPreview.previewImageURL,
                loading: store.sliderPreview.previewLoading,
                imageHeight: bubbleLayout.imageHeight
            )
            .frame(width: bubbleLayout.width)
            .offset(x: bubbleLeadingX)
            .allowsHitTesting(false)
        }
        .frame(height: bubbleLayout.rowHeight)
        .environment(\.layoutDirection, .leftToRight)
        .transition(.opacity)
    }

    private func readerControlPanel(
        displayPageNumber: Int,
        sliderContext: ReaderSliderContext
    ) -> some View {
        VStack(spacing: 10) {
            readerActionRow(displayPageNumber: displayPageNumber)
            readerPageSlider(context: sliderContext)
        }
        .padding(.horizontal, 14)
        .padding(.top, 12)
        .padding(.bottom, 10)
        .background(
            .ultraThinMaterial,
            in: RoundedRectangle(cornerRadius: ReaderToolbarMetrics.panelCornerRadius, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: ReaderToolbarMetrics.panelCornerRadius, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
        }
        .shadow(color: Color.black.opacity(0.18), radius: 18, x: 0, y: 8)
    }

    private func readerActionRow(displayPageNumber: Int) -> some View {
        let autoPageDisabled = store.readDirection == ReadDirection.upDown.rawValue

        return HStack(spacing: 10) {
            readerToolbarButton(
                systemImage: "arrow.clockwise",
                tint: Color(uiColor: .systemBlue),
                disabled: store.cached,
                accessibilityLabel: "archive.reader.reload.currentPage"
            ) {
                let indexString = store.pages[store.safeCurrentPageIndex].id
                store.send(.page(.element(id: indexString, action: .load(true))))
            }

            readerToolbarButton(
                systemImage: "play.fill",
                tint: Color(uiColor: .systemPurple),
                disabled: autoPageDisabled,
                accessibilityLabel: "archive.reader.autoPage"
            ) {
                store.send(.showAutoPageConfig)
            }

            Spacer(minLength: 2)

            pageCounter(
                currentPage: displayPageNumber,
                pageCount: store.archivePageCount
            )

            Spacer(minLength: 2)

            Menu {
                Picker("settings.read.layout", selection: Binding(
                    get: { store.pageLayoutMode },
                    set: { store.send(.pageLayoutModeChanged($0)) }
                )) {
                    ForEach(ReaderPageLayoutMode.allCases, id: \.self) { mode in
                        Label(LocalizedStringKey(mode.localizationKey), systemImage: mode.systemImage).tag(mode)
                    }
                }
            } label: {
                readerToolbarGlyph(
                    systemImage: store.pageLayoutMode.systemImage,
                    tint: Color(uiColor: .systemGreen)
                )
            }
            .disabled(!store.canToggleDoublePageLayout)
            .buttonStyle(.plain)
            .clipShape(Circle())
            .opacity(store.canToggleDoublePageLayout ? 1 : 0.4)
            .accessibilityLabel(Text("settings.read.layout"))
            .accessibilityValue(Text(LocalizedStringKey(store.pageLayoutMode.localizationKey)))

            readerMoreMenu()
        }
    }

    private func readerMoreMenu() -> some View {
        let cacheActionRemoves = store.cached || store.inCache

        return Menu {
            if store.canUseStamps {
                Button {
                    store.send(.toggleStampsVisibility)
                } label: {
                    if store.showStamps {
                        Label("archive.reader.stamps.hide", systemImage: "mappin.slash")
                    } else {
                        Label("archive.reader.stamps.show", systemImage: "mappin")
                    }
                }
            }

            Button {
                store.send(.setThumbnail)
            } label: {
                Label("archive.thumbnail.current", systemImage: "photo.artframe")
            }
            .disabled(store.settingThumbnail || store.cached)

            if cacheActionRemoves {
                Button(role: .destructive) {
                    store.send(.removeCache)
                } label: {
                    Label("archive.cache.remove", systemImage: "trash")
                }
            } else {
                Button {
                    store.send(.downloadPages)
                } label: {
                    Label("archive.cache.add", systemImage: "tray.and.arrow.down")
                }
            }
        } label: {
            readerToolbarGlyph(systemImage: "ellipsis", tint: Color.primary)
        }
        .menuOrder(.fixed)
        .buttonStyle(.plain)
        .clipShape(Circle())
        .accessibilityLabel(Text("archive.reader.more"))
    }

    private func pageCounter(currentPage: Int, pageCount: Int) -> some View {
        HStack(spacing: 4) {
            Text("\(currentPage)")
            Text(verbatim: "/")
                .foregroundStyle(.secondary)
            Text("\(pageCount)")
        }
        .font(.callout.weight(.semibold))
        .monospacedDigit()
        .lineLimit(1)
        .minimumScaleFactor(0.8)
        .padding(.horizontal, 12)
        .frame(minWidth: 86, minHeight: 36)
        .foregroundStyle(.primary)
        .background(Color(uiColor: .tertiarySystemFill), in: Capsule())
        .environment(\.layoutDirection, .leftToRight)
        .accessibilityLabel(
            Text(verbatim: pageCounterAccessibilityLabel(currentPage: currentPage, pageCount: pageCount))
        )
    }

    private func pageCounterAccessibilityLabel(currentPage: Int, pageCount: Int) -> String {
        let format = String(localized: "archive.reader.page.accessibility %lld %lld")
        return String(format: format, Int64(currentPage), Int64(pageCount))
    }

    private func readerToolbarButton(
        systemImage: String,
        tint: Color,
        disabled: Bool = false,
        accessibilityLabel: LocalizedStringKey,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            readerToolbarGlyph(systemImage: systemImage, tint: tint, disabled: disabled)
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .opacity(disabled ? 0.42 : 1)
        .accessibilityLabel(Text(accessibilityLabel))
    }

    private func readerToolbarGlyph(
        systemImage: String,
        tint: Color,
        disabled: Bool = false
    ) -> some View {
        Image(systemName: systemImage)
            .font(.system(size: 17, weight: .semibold))
            .foregroundStyle(disabled ? Color.secondary : tint)
            .frame(width: ReaderToolbarMetrics.buttonSize, height: ReaderToolbarMetrics.buttonSize)
            .background(Color(uiColor: .secondarySystemBackground).opacity(0.82), in: Circle())
            .overlay {
                Circle()
                    .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
            }
    }

    private func readerPageSlider(context: ReaderSliderContext) -> some View {
        HStack(spacing: ReaderToolbarMetrics.chapterMenuSpacing) {
            if store.shouldShowChapterMenu {
                readerChapterMenu()
            }

            readerSliderTrack(context: context)
        }
        .frame(height: store.shouldShowChapterMenu ? ReaderToolbarMetrics.buttonSize : 34)
    }

    private func readerSliderTrack(context: ReaderSliderContext) -> some View {
        GeometryReader { geometry in
            let sliderWidth = max(geometry.size.width - context.horizontalPadding * 2, 1)

            ZStack {
                Slider(
                    value: .constant(context.displayValue),
                    in: 0...Double(context.maxIndex),
                    step: 1
                )
                .tint(Color(uiColor: .systemBlue))
                .padding(.horizontal, context.horizontalPadding)
                .scaleEffect(x: context.isRightToLeft ? -1 : 1, y: 1)
                .allowsHitTesting(false)

                Rectangle()
                    .fill(Color.clear)
                    .contentShape(Rectangle())
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { value in
                                if !store.sliderPreview.dragging {
                                    store.send(.sliderPreview(.dragStarted))
                                }
                                sendSliderDragChanged(
                                    locationX: value.location.x,
                                    sliderWidth: sliderWidth,
                                    context: context
                                )
                            }
                            .onEnded { value in
                                sendSliderDragChanged(
                                    locationX: value.location.x,
                                    sliderWidth: sliderWidth,
                                    context: context
                                )
                                store.send(.sliderPreview(.dragEnded))
                            }
                    )
            }
        }
        .frame(height: 34)
        .environment(\.layoutDirection, .leftToRight)
        .accessibilityLabel(Text("archive.reader.page.slider"))
    }

    private func readerChapterMenu() -> some View {
        let editablePages = store.editableChapterPages
        return Menu {
            ForEach(store.chapters) { chapter in
                Button(chapter.name) {
                    store.send(.chapterSelected(chapter.page))
                }
            }
            if !store.chapters.isEmpty, !editablePages.isEmpty || store.canAddChapter {
                Divider()
            }
            if !editablePages.isEmpty {
                Menu {
                    ForEach(store.chapters.filter { editablePages.contains($0.page) }) { chapter in
                        Button(chapter.name) {
                            guard let edit = store.state.chapterEditingTarget(for: chapter.page) else { return }
                            store.send(.chapter(.editingRequested(
                                target: edit.target,
                                title: edit.title,
                                editable: editablePages.contains(chapter.page)
                            )))
                        }
                        .disabled(store.chapter.requestInFlight)
                    }
                } label: {
                    Label("archive.reader.chapters.edit", systemImage: "pencil")
                }
            }
            if store.canAddChapter {
                Button {
                    guard let target = store.state.chapterCreationTarget() else { return }
                    store.send(.chapter(.creationRequested(target: target, cached: store.cached)))
                } label: {
                    Label("archive.reader.chapter.add", systemImage: "plus")
                }
                .disabled(store.chapter.requestInFlight)
            }
        } label: {
            readerToolbarGlyph(systemImage: "list.bullet.rectangle", tint: Color.indigo)
        }
        .menuOrder(.fixed)
        .buttonStyle(.plain)
        .clipShape(Circle())
        .accessibilityLabel(Text("archive.reader.chapters"))
    }

    private func sendSliderDragChanged(
        locationX: CGFloat,
        sliderWidth: CGFloat,
        context: ReaderSliderContext
    ) {
        store.send(
            .sliderPreview(.dragChanged(
                SliderPreviewPositioning.pageIndex(
                    at: locationX,
                    sliderWidth: sliderWidth,
                    horizontalPadding: context.horizontalPadding,
                    sliderMaxIndex: context.maxIndex,
                    isRightToLeft: context.isRightToLeft
                )
            ))
        )
    }
}

private struct ReaderSliderContext {
    let displayValue: Double
    let maxIndex: Int
    let horizontalPadding: CGFloat
    let isRightToLeft: Bool
}

private enum ReaderToolbarMetrics {
    static let outerHorizontalPadding: CGFloat = 12
    static let bottomPadding: CGFloat = 12
    static let maxPanelWidth: CGFloat = 700
    static let panelCornerRadius: CGFloat = 26
    static let previewBottomSpacing: CGFloat = 12
    static let sliderHorizontalPadding: CGFloat = 16
    static let buttonSize: CGFloat = 44
    static let chapterMenuSpacing: CGFloat = 10
    static let chapterMenuInset = buttonSize + chapterMenuSpacing
}

enum SliderPreviewPositioning {
    static func visualNormalized(
        pageIndex: Int,
        pageCount: Int,
        isRightToLeft: Bool
    ) -> CGFloat {
        guard pageCount > 1 else { return 0 }
        let clampedIndex = ReaderPositioning.clampedPageIndex(pageIndex, pageCount: pageCount)
        let logicalNormalized = CGFloat(clampedIndex) / CGFloat(pageCount - 1)
        return isRightToLeft ? (1 - logicalNormalized) : logicalNormalized
    }

    static func bubbleLeadingX(
        pageIndex: Int,
        pageCount: Int,
        track: SliderPreviewTrackGeometry,
        isRightToLeft: Bool
    ) -> CGFloat {
        let sliderWidth = max(
            track.rowWidth
                - track.leadingInset
                - track.trailingInset
                - track.sliderHorizontalPadding * 2,
            1
        )
        let thumbCenterX = track.leadingInset + track.sliderHorizontalPadding + (
            sliderWidth * visualNormalized(
                pageIndex: pageIndex,
                pageCount: pageCount,
                isRightToLeft: isRightToLeft
            )
        )
        let maxLeading = max(track.rowWidth - track.bubbleWidth, 0)
        return max(0, min(thumbCenterX - (track.bubbleWidth / 2), maxLeading))
    }

    static func pageIndex(
        at locationX: CGFloat,
        sliderWidth: CGFloat,
        horizontalPadding: CGFloat,
        sliderMaxIndex: Int,
        isRightToLeft: Bool
    ) -> Int {
        let adjustedX = min(
            max(locationX - horizontalPadding, 0),
            sliderWidth
        )
        let visualNormalized = sliderWidth == 0 ? 0 : adjustedX / sliderWidth
        let logicalNormalized = isRightToLeft ? (1 - visualNormalized) : visualNormalized
        return Int((logicalNormalized * CGFloat(sliderMaxIndex)).rounded())
    }
}

struct SliderPreviewTrackGeometry {
    let rowWidth: CGFloat
    let sliderHorizontalPadding: CGFloat
    let bubbleWidth: CGFloat
    let leadingInset: CGFloat
    let trailingInset: CGFloat

    init(
        rowWidth: CGFloat,
        sliderHorizontalPadding: CGFloat,
        bubbleWidth: CGFloat,
        leadingInset: CGFloat = 0,
        trailingInset: CGFloat = 0
    ) {
        self.rowWidth = rowWidth
        self.sliderHorizontalPadding = sliderHorizontalPadding
        self.bubbleWidth = bubbleWidth
        self.leadingInset = leadingInset
        self.trailingInset = trailingInset
    }
}

private struct SliderPreviewBubble: View {
    let imageURL: URL?
    let loading: Bool
    let imageHeight: CGFloat

    private var previewImage: UIImage? {
        guard let imageURL,
              let image = UIImage(contentsOfFile: imageURL.path(percentEncoded: false)) else {
            return nil
        }
        if let preparedImage = image.preparingForDisplay() {
            return preparedImage
        }
        return image
    }

    var body: some View {
        Group {
            if let previewImage {
                Image(uiImage: previewImage)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color(.secondarySystemBackground))
            } else if loading {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color(.secondarySystemBackground))
            } else {
                Image(systemName: "photo")
                    .font(.title2)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color(.secondarySystemBackground))
            }
        }
        .frame(height: imageHeight)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .padding(12)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .shadow(color: .black.opacity(0.18), radius: 16, y: 6)
    }
}
