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

    private let suggestionsTableView: UITableView = {
        let tableView = UITableView()
        tableView.translatesAutoresizingMaskIntoConstraints = false
        tableView.isHidden = true
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
            return 300
        } else {
            return 600
        }
    }()
    private let suggestionsRowHeight: CGFloat = 45

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

        view.addSubview(suggestionsTableView)

        suggestionsHeightConstraint = suggestionsTableView.heightAnchor.constraint(equalToConstant: 0)
        suggestionsHeightConstraint?.isActive = true

        if UIDevice.current.userInterfaceIdiom == .phone {
            NSLayoutConstraint.activate([
                // Archive list fills
                archiveListViewController.view.topAnchor.constraint(equalTo: view.topAnchor),
                archiveListViewController.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
                archiveListViewController.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
                archiveListViewController.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),

                // Suggestions table anchors (top under safe area so it visually appears below nav/search bar)
                suggestionsTableView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
                suggestionsTableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
                suggestionsTableView.trailingAnchor.constraint(equalTo: view.trailingAnchor)
            ])
        } else {
            NSLayoutConstraint.activate([
                // Search bar constraints
                searchBar.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
                searchBar.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 8),
                searchBar.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -8),

                suggestionsTableView.topAnchor.constraint(equalTo: searchBar.bottomAnchor, constant: 8),
                suggestionsTableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
                suggestionsTableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),

                archiveListViewController.view.topAnchor.constraint(equalTo: searchBar.bottomAnchor, constant: 8),
                archiveListViewController.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
                archiveListViewController.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
                archiveListViewController.view.bottomAnchor.constraint(equalTo: view.bottomAnchor)
            ])
        }
    }

    private func setupDelegates() {
        if UIDevice.current.userInterfaceIdiom == .phone {
            searchController.searchBar.delegate = self
        } else {
            searchBar.delegate = self
        }

        suggestionsTableView.delegate = self
        suggestionsTableView.dataSource = self
        suggestionsTableView.register(UITableViewCell.self, forCellReuseIdentifier: "SuggestionCellV2")
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
                self.suggestionsHeightConstraint?.constant = maxSuggestionsHeight
                self.suggestionsTableView.isHidden = false
                self.view.layoutIfNeeded()
            }
        }
    }

    // MARK: - Suggestions Handling
    private func updateSuggestionsVisibility(for searchText: String) {
        if !store.suggestedTag.isEmpty {
            let contentHeight = CGFloat(store.suggestedTag.count) * suggestionsRowHeight
            let newHeight = min(contentHeight, maxSuggestionsHeight)
            UIView.animate(withDuration: 0.25) {
                self.suggestionsHeightConstraint?.constant = newHeight
                self.suggestionsTableView.isHidden = false
                self.view.layoutIfNeeded()
            }
        } else {
            UIView.animate(withDuration: 0.25) {
                self.suggestionsHeightConstraint?.constant = 0
                self.suggestionsTableView.isHidden = true
                self.view.layoutIfNeeded()
            }
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
        suggestionsTableView.isHidden = true
        suggestionsHeightConstraint?.constant = 0
        searchBar.resignFirstResponder()
    }
}

// MARK: - UITableViewDataSource / UITableViewDelegate
extension UISearchViewV2Controller: UITableViewDataSource, UITableViewDelegate {
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int { store.suggestedTag.count }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "SuggestionCellV2", for: indexPath)
        var content = cell.defaultContentConfiguration()
        let tagWithType = store.suggestedTag[indexPath.row]
        content.text = tagWithType.tag
        content.image = tagWithType.type == .popular ? UIImage(systemName: "flame") : UIImage(systemName: "tag")
        content.imageProperties.tintColor = .label
        cell.contentConfiguration = content
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
        UIView.animate(withDuration: 0.25) {
            self.suggestionsHeightConstraint?.constant = 0
            tableView.isHidden = true
            self.view.layoutIfNeeded()
        }
        tableView.deselectRow(at: indexPath, animated: true)
    }
}
