import ComposableArchitecture
import OrderedCollections
import UIKit

struct ArchiveListSelectionToolbarState: Equatable {
    struct CategoryMenuItem: Equatable {
        let id: String
        let name: String
    }

    let selecting: Bool
    let selected: OrderedSet<String>
    let actionsEnabled: Bool
    let staticCategoryId: String?
    let categories: [CategoryMenuItem]
}

extension UIArchiveListViewController {
    func setupToolbar() {
        if store.selectMode == .active {
            parent?.navigationItem.rightBarButtonItem = UIBarButtonItem(
                title: String(localized: "done"),
                primaryAction: UIAction { [weak self] _ in
                    self?.store.send(.toggleSelectionMode)
                }
            )
            parent?.navigationItem.rightBarButtonItem?.isEnabled = !store.batchActionInProgress
            return
        }
        let sortGroup = UIMenu(title: "", options: .displayInline, children: makeSortMenuActions())
        let otherGroup = UIMenu(title: "", options: .displayInline, children: makeOtherMenuActions())
        let menu = UIMenu(title: "", children: [sortGroup, otherGroup, makeSelectMenuAction()])
        let menuButton = UIBarButtonItem(
            image: UIImage(systemName: "arrow.up.arrow.down.circle"),
            menu: menu
        )
        parent?.navigationItem.rightBarButtonItem = menuButton
    }

    func renderSelectionToolbarIfNeeded() {
        let selecting = store.selectMode == .active
        let selected = store.selected
        let actionsEnabled = store.canStartBatchAction
        let staticCategoryId = store.currentStaticCategoryId
        let categories = store.categoryItems.filter { $0.search.isEmpty }.map {
            ArchiveListSelectionToolbarState.CategoryMenuItem(id: $0.id, name: $0.name)
        }
        let toolbarState = ArchiveListSelectionToolbarState(
            selecting: selecting,
            selected: selected,
            actionsEnabled: actionsEnabled,
            staticCategoryId: staticCategoryId,
            categories: categories
        )
        guard toolbarState != renderedSelectionToolbarState else { return }
        renderedSelectionToolbarState = toolbarState
        refreshVisibleSelectionCells(selecting: selecting, selected: selected)

        let (toolbarItems, deleteButton) = makeSelectionToolbarItems(for: toolbarState)
        parent?.toolbarItems = toolbarItems
        updateSelectionToolbarAppearance()
        deleteButton.tintColor = .systemRed
        updateSelectionBarVisibility()
    }

    func updateSelectionToolbarAppearance() {
        let foreground = UIColor.label.resolvedColor(with: parent?.traitCollection ?? traitCollection)
        parent?.toolbarItems?.dropLast().forEach { $0.tintColor = foreground }
    }

    func updateSelectionBarVisibility() {
        guard let navigationController, navigationController.topViewController === parent else { return }
        let selecting = store.selectMode == .active
        parent?.navigationItem.setHidesBackButton(selecting, animated: false)
        navigationController.setToolbarHidden(!selecting, animated: false)
        updateTabBarVisibility()
    }

    func updateTabBarVisibility() {
        guard let navigationController, navigationController.topViewController === parent else { return }
        let hideTabs = store.selectMode == .active || navigationController.viewControllers.first !== parent
        if #available(iOS 18.0, *) {
            if tabBarController?.isTabBarHidden != hideTabs {
                tabBarController?.setTabBarHidden(hideTabs, animated: false)
            }
        } else {
            tabBarController?.tabBar.isHidden = hideTabs
        }
    }

    func presentPageInput() {
        let pageCount = store.pageCount
        guard pageCount > 1 else { return }

        let alert = UIAlertController(
            title: String(localized: "archive.list.page.jump.title"),
            message: String(
                format: String(localized: "archive.list.page.jump.message %lld"),
                Int64(pageCount)
            ),
            preferredStyle: .alert
        )
        alert.addTextField { field in
            field.keyboardType = .numberPad
            field.textAlignment = .center
            field.text = String(self.store.currentPage + 1)
            field.clearButtonMode = .whileEditing
        }
        alert.addAction(UIAlertAction(title: String(localized: "cancel"), style: .cancel))
        let goAction = UIAlertAction(
            title: String(localized: "archive.list.page.jump.go"),
            style: .default
        ) { [weak self, weak alert] _ in
            guard let self, let text = alert?.textFields?.first?.text,
                  let requested = Int(text.trimmingCharacters(in: .whitespaces)) else { return }
            // Displayed page numbers are one-based; the reducer works in zero-based pages.
            goToPage(requested - 1)
        }
        alert.addAction(goAction)
        present(alert, animated: true)
    }

    @objc func confirmBatchDeletion(_ sender: UIBarButtonItem) {
        guard store.canStartBatchAction else { return }
        let confirmation = UIAlertController(
            title: String(localized: "archive.selected.delete"),
            message: nil,
            preferredStyle: .actionSheet
        )
        confirmation.addAction(UIAlertAction(
            title: String(localized: "delete"),
            style: .destructive
        ) { [weak self] _ in
            self?.store.send(.confirmDelete)
        })
        confirmation.addAction(UIAlertAction(title: String(localized: "cancel"), style: .cancel))
        confirmation.popoverPresentationController?.barButtonItem = sender
        present(confirmation, animated: true)
    }

    @objc func promptForTankoubonName(_: UIBarButtonItem) {
        guard store.canStartBatchAction else { return }
        guard !store.selected.contains(where: \.isTankoubonArchiveId) else {
            store.send(.setErrorMessage(String(localized: "archive.selected.tankoubon.nested.error")))
            return
        }
        let alert = UIAlertController(
            title: String(localized: "archive.selected.tankoubon.create"),
            message: nil,
            preferredStyle: .alert
        )
        alert.addTextField { field in
            field.placeholder = String(localized: "archive.selected.tankoubon.name")
        }
        alert.addAction(UIAlertAction(title: String(localized: "cancel"), style: .cancel))
        alert.addAction(UIAlertAction(
            title: String(localized: "archive.selected.tankoubon.create"),
            style: .default
        ) { [weak self, weak alert] _ in
            self?.store.send(.createTankoubon(alert?.textFields?.first?.text ?? ""))
        })
        present(alert, animated: true)
    }

    @objc func confirmBatchCategoryRemoval(_ sender: UIBarButtonItem) {
        guard store.canStartBatchAction,
              store.currentStaticCategoryId != nil else { return }
        let confirmation = UIAlertController(
            title: String(localized: "archive.selected.category.remove"),
            message: nil,
            preferredStyle: .actionSheet
        )
        confirmation.addAction(UIAlertAction(
            title: String(localized: "remove"),
            style: .destructive
        ) { [weak self] _ in
            self?.store.send(.confirmRemoveFromCategory)
        })
        confirmation.addAction(UIAlertAction(title: String(localized: "cancel"), style: .cancel))
        confirmation.popoverPresentationController?.barButtonItem = sender
        present(confirmation, animated: true)
    }
}

private extension UIArchiveListViewController {
    static func clearCheckmarkImage() -> UIImage? {
        UIImage(systemName: "checkmark")?.withTintColor(.clear, renderingMode: .alwaysOriginal)
    }

    func makeSortMenuActions() -> [UIAction] {
        SearchSort.allCases.filter { $0 != SearchSort.random }.map { sort in
            let label = NSLocalizedString("settings.archive.list.order.\(sort)", comment: "")
            let isSelected = store.searchSort == sort.rawValue
                || (store.searchSort == store.searchSortCustom && sort == SearchSort.custom)
            let image: UIImage? = if isSelected {
                UIImage(systemName: store.searchSortOrder == "asc" ? "arrow.up" : "arrow.down")
            } else {
                Self.clearCheckmarkImage()
            }
            return UIAction(title: label, image: image) { [weak self] _ in
                guard let self else { return }
                let matchesCurrent = store.searchSort == sort.rawValue
                    || (store.searchSort == store.searchSortCustom && sort == SearchSort.custom)
                if matchesCurrent {
                    store.send(.setSearchSortOrder(store.searchSortOrder == "asc" ? "desc" : "asc"))
                } else {
                    store.send(.setSearchSort(sort == SearchSort.custom ? store.searchSortCustom : sort.rawValue))
                }
            }
        }
    }

    func makeOtherMenuActions() -> [UIAction] {
        let randomAction = UIAction(
            title: String(localized: "settings.archive.list.order.random"),
            image: store.searchSort == SearchSort.random.rawValue
                ? UIImage(systemName: "checkmark")
                : Self.clearCheckmarkImage()
        ) { [weak self] _ in
            self?.store.send(.setSearchSort(SearchSort.random.rawValue))
        }
        let hideReadAction = UIAction(
            title: String(localized: "settings.view.hideRead"),
            image: store.hideRead ? UIImage(systemName: "checkmark") : Self.clearCheckmarkImage()
        ) { [weak self] _ in
            self?.store.send(.toggleHideRead)
        }
        return [randomAction, hideReadAction]
    }

    func makeSelectMenuAction() -> UIAction {
        UIAction(
            title: String(localized: "select"),
            image: Self.clearCheckmarkImage()
        ) { [weak self] _ in
            guard let self else { return }
            store.send(.toggleSelectionMode)
            if store.selectMode == .active && store.categoryItems.isEmpty {
                store.send(.loadCategory)
            }
        }
    }

    func refreshVisibleSelectionCells(selecting: Bool, selected: OrderedSet<String>) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            for indexPath in collectionView.indexPathsForVisibleItems {
                guard let item = dataSource.itemIdentifier(for: indexPath),
                      let cell = collectionView.cellForItem(at: indexPath) as? UIArchiveCell else { continue }
                cell.configure(
                    with: item,
                    database: database,
                    selecting: selecting,
                    selected: selected.contains(item.id)
                )
            }
        }
    }

    func makeSelectionToolbarItems(
        for state: ArchiveListSelectionToolbarState
    ) -> (items: [UIBarButtonItem], deleteButton: UIBarButtonItem) {
        let count = UIBarButtonItem.selectionCount(state.selected.count)
        let categoryAction = makeCategoryToolbarItem(for: state)
        let createTankoubon = UIBarButtonItem(
            image: UIImage(systemName: "book.badge.plus"),
            style: .plain,
            target: self,
            action: #selector(promptForTankoubonName(_:))
        )
        createTankoubon.accessibilityLabel = String(localized: "archive.selected.tankoubon.create")
        createTankoubon.isEnabled = state.actionsEnabled
        let download = UIBarButtonItem(
            image: UIImage(systemName: "tray.and.arrow.down"),
            primaryAction: UIAction { [weak self] _ in
                self?.store.send(.cacheSelected)
            }
        )
        download.accessibilityLabel = String(localized: "archive.cache.add")
        download.isEnabled = state.actionsEnabled
        let delete = UIBarButtonItem(
            image: UIImage(systemName: "trash"),
            style: .plain,
            target: self,
            action: #selector(confirmBatchDeletion(_:))
        )
        delete.accessibilityLabel = String(localized: "archive.delete")
        delete.isEnabled = state.actionsEnabled
        return ([count, .flexibleSpace(), categoryAction, createTankoubon, download, delete], delete)
    }

    func makeCategoryToolbarItem(for state: ArchiveListSelectionToolbarState) -> UIBarButtonItem {
        if state.staticCategoryId != nil {
            let button = UIBarButtonItem(
                image: UIImage(systemName: "folder.badge.minus"),
                style: .plain,
                target: self,
                action: #selector(confirmBatchCategoryRemoval(_:))
            )
            button.accessibilityLabel = String(localized: "remove")
            button.isEnabled = state.actionsEnabled
            return button
        }
        let categoryActions = state.categories.map { category in
            UIAction(title: category.name) { [weak self] _ in
                self?.store.send(.addArchivesToCategory(category.id))
            }
        }
        let button = UIBarButtonItem(
            image: UIImage(systemName: "folder.badge.plus"),
            menu: UIMenu(
                title: String(localized: "archive.selected.category.add"),
                children: categoryActions
            )
        )
        button.accessibilityLabel = String(localized: "archive.selected.category.add")
        button.isEnabled = state.actionsEnabled && !categoryActions.isEmpty
        return button
    }
}
