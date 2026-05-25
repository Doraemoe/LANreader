import ComposableArchitecture
import SwiftUI
import UIKit

@Reducer public struct SearchFeature {
    @ObservableState
    public struct State: Equatable {
        var keyword = ""
        var suggestedTag = [TagWithType]()
        var popularTag = [TagWithType]()
        var archiveList = ArchiveListFeature.State(
            filter: SearchFilter(category: nil, filter: nil),
            loadOnAppear: false,
            currentTab: .search
        )
    }

    public enum Action: Equatable, BindableAction {
        case binding(BindingAction<State>)
        case generateSuggestion(String)
        case loadPopularTag
        case suggestionTapped(TagWithType)
        case searchSubmit(String)
        case archiveList(ArchiveListFeature.Action)
    }

    @Dependency(\.lanraragiService) var service
    @Dependency(\.appDatabase) var database

    enum CancelId { case search }

    public var body: some ReducerOf<Self> {

        Scope(state: \.archiveList, action: \.archiveList) {
            ArchiveListFeature()
        }

        BindingReducer()
        Reduce { state, action in
            switch action {
            case let .generateSuggestion(searchText):
                let lastToken = searchText.split(
                    separator: " ",
                    omittingEmptySubsequences: false
                ).last.map(String.init) ?? ""
                guard !lastToken.isEmpty else {
                    state.suggestedTag = state.popularTag
                    return .none
                }
                do {
                    let result = try database.searchTag(keyword: lastToken)
                    state.suggestedTag = result.map {
                        TagWithType(tag: $0.tag, type: .suggested)
                    }
                } catch {
                    state.suggestedTag = state.popularTag
                }
                return .none
            case .loadPopularTag:
                if let result = try? database.popularTag() {
                    state.popularTag = result.map {
                        TagWithType(tag: $0.tag, type: .popular)
                    }
                    state.suggestedTag = state.popularTag
                }
                return .none
            case let .suggestionTapped(tagWithType):
                let validKeyword = if tagWithType.type == .suggested {
                    state.keyword.split(separator: " ").dropLast(1).joined(separator: " ")
                } else {
                    state.keyword.trimmingCharacters(in: .whitespaces)
                }
                state.keyword = "\(validKeyword) \(tagWithType.tag)$,"
                return .none
            case let .searchSubmit(keyword):
                guard !keyword.isEmpty else {
                    return .none
                }
                state.archiveList.filter = SearchFilter(category: nil, filter: keyword)
                return .none
            case .binding:
                return .none
            case .archiveList:
                return .none
            }
        }
    }
}

class UISearchViewV2Controller: UIViewController {
    private let store: StoreOf<SearchFeature>

    // MARK: - UI
    private lazy var searchController: UISearchController = {
        let controller = UISearchController(searchResultsController: nil)
        controller.obscuresBackgroundDuringPresentation = false
        controller.hidesNavigationBarDuringPresentation = false
        controller.searchBar.placeholder = String(localized: "search")
        return controller
    }()

    private let searchBar: UISearchBar = {
        let searchBar = UISearchBar()
        searchBar.placeholder = String(localized: "search")
        searchBar.translatesAutoresizingMaskIntoConstraints = false
        searchBar.searchBarStyle = .minimal
        return searchBar
    }()

    private let suggestionsContainerView: UIView = {
        let view = UIView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.isHidden = true
        view.layer.shadowColor = UIColor.black.cgColor
        view.layer.shadowOpacity = 0.12
        view.layer.shadowRadius = 18
        view.layer.shadowOffset = CGSize(width: 0, height: 10)
        return view
    }()

    private let suggestionsBackgroundView: UIVisualEffectView = {
        let blur = UIBlurEffect(style: .systemChromeMaterial)
        let view = UIVisualEffectView(effect: blur)
        view.translatesAutoresizingMaskIntoConstraints = false
        view.clipsToBounds = true
        view.layer.cornerRadius = 22
        view.layer.borderColor = UIColor.label.withAlphaComponent(0.08).cgColor
        view.layer.borderWidth = 1
        return view
    }()

    private let suggestionsTableView: UITableView = {
        let tableView = UITableView()
        tableView.translatesAutoresizingMaskIntoConstraints = false
        tableView.isHidden = true
        tableView.backgroundColor = .clear
        tableView.separatorStyle = .none
        tableView.rowHeight = 58
        tableView.showsVerticalScrollIndicator = false
        tableView.keyboardDismissMode = .onDrag
        tableView.contentInset = UIEdgeInsets(top: 6, left: 0, bottom: 6, right: 0)
        return tableView
    }()

    // Archive list child (same as original UISearchView)
    private lazy var archiveListViewController: UIArchiveListViewController = {
        UIArchiveListViewController(
            store: store.scope(state: \.archiveList, action: \.archiveList)
        )
    }()

    // Constraints for animated height changes
    private var suggestionsHeightConstraint: NSLayoutConstraint?

    // Constants
    private let maxSuggestionsHeight: CGFloat = {
        if UIDevice.current.userInterfaceIdiom == .phone {
            return 340
        } else {
            return 540
        }
    }()
    private let suggestionsRowHeight: CGFloat = 58
    private let suggestionsVerticalPadding: CGFloat = 12

    // MARK: - Init
    init(store: StoreOf<SearchFeature>) {
        self.store = store
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    // MARK: - Lifecycle
    override func viewDidLoad() {
        super.viewDidLoad()
        setupNavigationSearch()
        setupLayout()
        setupDelegates()
        setupObserve()
        store.send(.loadPopularTag)
        navigationItem.title = String(localized: "search")
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        if navigationController?.viewControllers.count == 1 {
            if #available(iOS 18.0, *) {
                tabBarController?.setTabBarHidden(false, animated: false)
            } else {
                tabBarController?.tabBar.isHidden = false
            }
        }
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        suggestionsContainerView.layer.shadowPath = UIBezierPath(
            roundedRect: suggestionsContainerView.bounds,
            cornerRadius: 22
        ).cgPath
    }

    // MARK: - Setup
    private func setupNavigationSearch() {
        if UIDevice.current.userInterfaceIdiom == .phone {
            navigationItem.searchController = searchController
            navigationItem.hidesSearchBarWhenScrolling = false
            definesPresentationContext = true
            searchController.searchBar.text = store.keyword
        }
    }

    private func setupLayout() {
        view.backgroundColor = .systemBackground

        if UIDevice.current.userInterfaceIdiom != .phone {
            searchBar.text = store.keyword
            view.addSubview(searchBar)
        }

        // Child archive list
        add(archiveListViewController)

        view.addSubview(suggestionsContainerView)
        suggestionsContainerView.addSubview(suggestionsBackgroundView)
        suggestionsBackgroundView.contentView.addSubview(suggestionsTableView)

        suggestionsHeightConstraint = suggestionsContainerView.heightAnchor.constraint(equalToConstant: 0)
        suggestionsHeightConstraint?.isActive = true

        if UIDevice.current.userInterfaceIdiom == .phone {
            NSLayoutConstraint.activate([
                // Archive list fills
                archiveListViewController.view.topAnchor.constraint(equalTo: view.topAnchor),
                archiveListViewController.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
                archiveListViewController.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
                archiveListViewController.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),

                // Suggestions table anchors (top under safe area so it visually appears below nav/search bar)
                suggestionsContainerView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 8),
                suggestionsContainerView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
                suggestionsContainerView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16)
            ])
        } else {
            NSLayoutConstraint.activate([
                // Search bar constraints
                searchBar.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
                searchBar.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 8),
                searchBar.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -8),

                suggestionsContainerView.topAnchor.constraint(equalTo: searchBar.bottomAnchor, constant: 10),
                suggestionsContainerView.leadingAnchor.constraint(equalTo: searchBar.leadingAnchor),
                suggestionsContainerView.trailingAnchor.constraint(equalTo: searchBar.trailingAnchor),

                archiveListViewController.view.topAnchor.constraint(equalTo: searchBar.bottomAnchor, constant: 8),
                archiveListViewController.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
                archiveListViewController.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
                archiveListViewController.view.bottomAnchor.constraint(equalTo: view.bottomAnchor)
            ])
        }

        NSLayoutConstraint.activate([
            suggestionsBackgroundView.topAnchor.constraint(equalTo: suggestionsContainerView.topAnchor),
            suggestionsBackgroundView.leadingAnchor.constraint(equalTo: suggestionsContainerView.leadingAnchor),
            suggestionsBackgroundView.trailingAnchor.constraint(equalTo: suggestionsContainerView.trailingAnchor),
            suggestionsBackgroundView.bottomAnchor.constraint(equalTo: suggestionsContainerView.bottomAnchor),

            suggestionsTableView.topAnchor.constraint(equalTo: suggestionsBackgroundView.contentView.topAnchor),
            suggestionsTableView.leadingAnchor.constraint(equalTo: suggestionsBackgroundView.contentView.leadingAnchor),
            suggestionsTableView.trailingAnchor.constraint(
                equalTo: suggestionsBackgroundView.contentView.trailingAnchor
            ),
            suggestionsTableView.bottomAnchor.constraint(equalTo: suggestionsBackgroundView.contentView.bottomAnchor)
        ])
    }

    private func setupDelegates() {
        if UIDevice.current.userInterfaceIdiom == .phone {
            searchController.searchBar.delegate = self
        } else {
            searchBar.delegate = self
        }

        suggestionsTableView.delegate = self
        suggestionsTableView.dataSource = self
        suggestionsTableView.register(
            SearchSuggestionCell.self,
            forCellReuseIdentifier: SearchSuggestionCell.reuseIdentifier
        )
    }

    private func setupObserve() {
        observe { [weak self] in
            guard let self else { return }
            var searchText: String?
            if UIDevice.current.userInterfaceIdiom == .phone {
                searchText = searchController.searchBar.text
            } else {
                searchText = searchBar.text
            }
            if searchText?.isEmpty == true && !store.popularTag.isEmpty {
                suggestionsTableView.reloadData()
                updateSuggestionsVisibility(for: searchText ?? "", animated: false)
            }
        }
    }

    // MARK: - Suggestions Handling
    private func updateSuggestionsVisibility(for _: String, animated: Bool = true) {
        if !store.suggestedTag.isEmpty {
            let contentHeight = CGFloat(store.suggestedTag.count) * suggestionsRowHeight + suggestionsVerticalPadding
            let newHeight = min(contentHeight, maxSuggestionsHeight)

            let updates = {
                self.suggestionsHeightConstraint?.constant = newHeight
                self.suggestionsContainerView.isHidden = false
                self.suggestionsTableView.isHidden = false
                self.suggestionsTableView.showsVerticalScrollIndicator = contentHeight > self.maxSuggestionsHeight
                self.view.layoutIfNeeded()
            }
            if animated {
                UIView.animate(withDuration: 0.25, delay: 0, options: [.curveEaseOut]) {
                    updates()
                }
            } else {
                updates()
            }
        } else {
            hideSuggestions(animated: animated)
        }
    }

    private func hideSuggestions(animated: Bool = true) {
        let updates = {
            self.suggestionsHeightConstraint?.constant = 0
            self.suggestionsContainerView.isHidden = true
            self.suggestionsTableView.isHidden = true
            self.view.layoutIfNeeded()
        }
        if animated {
            UIView.animate(withDuration: 0.2, delay: 0, options: [.curveEaseIn]) {
                updates()
            }
        } else {
            updates()
        }
    }
}

// MARK: - UISearchBarDelegate
extension UISearchViewV2Controller: UISearchBarDelegate {
    func searchBar(_ searchBar: UISearchBar, textDidChange searchText: String) {
        Task { [weak self] in
            guard let self else { return }
            // Bind keyword into store state
            store.send(.binding(.set(\.keyword, searchText)))
            await store.send(.generateSuggestion(searchText)).finish()
            suggestionsTableView.reloadData()
            updateSuggestionsVisibility(for: searchText)
        }
    }

    func searchBarSearchButtonClicked(_ searchBar: UISearchBar) {
        guard let text = searchBar.text, !text.isEmpty else { return }
        store.send(.binding(.set(\.keyword, text)))
        store.send(.searchSubmit(text))
        hideSuggestions()
        searchBar.resignFirstResponder()
    }
}

// MARK: - UITableViewDataSource / UITableViewDelegate
extension UISearchViewV2Controller: UITableViewDataSource, UITableViewDelegate {
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int { store.suggestedTag.count }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(
            withIdentifier: SearchSuggestionCell.reuseIdentifier,
            for: indexPath
        )
        let tagWithType = store.suggestedTag[indexPath.row]
        if let cell = cell as? SearchSuggestionCell {
            cell.configure(with: tagWithType, isLast: indexPath.row == store.suggestedTag.count - 1)
        }
        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        let suggestion = store.suggestedTag[indexPath.row]
        store.send(.suggestionTapped(suggestion))
        if UIDevice.current.userInterfaceIdiom == .phone {
            searchController.searchBar.text = store.keyword
        } else {
            searchBar.text = store.keyword
        }
        hideSuggestions()
        tableView.deselectRow(at: indexPath, animated: true)
    }
}
