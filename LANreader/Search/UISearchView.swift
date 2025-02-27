import ComposableArchitecture
import SwiftUI
import UIKit

@Reducer public struct SearchFeature {
    @ObservableState
    public struct State: Equatable {
        var keyword = ""
        var suggestedTag = [String]()
        var archiveList = ArchiveListFeature.State(
            filter: SearchFilter(category: nil, filter: nil),
            loadOnAppear: false,
            currentTab: .search
        )
    }

    public enum Action: Equatable, BindableAction {
        case binding(BindingAction<State>)
        case generateSuggestion(String)
        case suggestionTapped(String)
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
                    state.suggestedTag = .init()
                    return .none
                }
                do {
                    let result = try database.searchTag(keyword: lastToken)
                    state.suggestedTag = result.map {
                        $0.tag
                    }
                } catch {
                    state.suggestedTag = .init()
                }
                return .none
            case let .suggestionTapped(tag):
                let validKeyword = state.keyword.split(separator: " ").dropLast(1).joined(separator: " ")
                state.keyword = "\(validKeyword) \(tag)$,"
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

class UISearchViewController: UIViewController {
    private let store: StoreOf<SearchFeature>

    // Constraint for dynamic height
    private var suggestionsHeightConstraint: NSLayoutConstraint?

    // Constants
    private let maxSuggestionsHeight: CGFloat = 300
    private let suggestionsRowHeight: CGFloat = 44

    init(store: StoreOf<SearchFeature>) {
        self.store = store
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

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
        tableView.layer.cornerRadius = 8
        tableView.layer.borderWidth = 1
        return tableView
    }()

    private func setupLayout() {
        searchBar.text = store.keyword
        view.addSubview(searchBar)

        let archiveListView = UIArchiveListViewController(
            store: store.scope(state: \.archiveList, action: \.archiveList)
        )
        add(archiveListView)

        view.addSubview(suggestionsTableView)

        suggestionsHeightConstraint = suggestionsTableView.heightAnchor.constraint(equalToConstant: 0)
        suggestionsHeightConstraint?.isActive = true

        NSLayoutConstraint.activate([
            // Search bar constraints
            searchBar.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            searchBar.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 8),
            searchBar.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -8),

            suggestionsTableView.topAnchor.constraint(equalTo: searchBar.bottomAnchor, constant: 8),
            suggestionsTableView.leadingAnchor.constraint(equalTo: searchBar.leadingAnchor),
            suggestionsTableView.trailingAnchor.constraint(equalTo: searchBar.trailingAnchor),

            archiveListView.view.topAnchor.constraint(equalTo: searchBar.bottomAnchor, constant: 8),
            archiveListView.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            archiveListView.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            archiveListView.view.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
    }

    private func setupDelegates() {
        searchBar.delegate = self
        suggestionsTableView.delegate = self
        suggestionsTableView.dataSource = self

        suggestionsTableView.register(UITableViewCell.self, forCellReuseIdentifier: "SuggestionCell")
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        setupLayout()
        setupDelegates()

        navigationItem.title = String(localized: "search")
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        if #available(iOS 18.0, *) {
            if navigationController?.viewControllers.count == 1 {
                tabBarController?.setTabBarHidden(false, animated: false)
            }
        }
    }

    private func updateSuggestionsVisibility(for searchText: String) {
        if !searchText.isEmpty && !store.suggestedTag.isEmpty {
            // Calculate height based on number of suggestions
            let contentHeight = CGFloat(store.suggestedTag.count) * suggestionsRowHeight
            let newHeight = min(contentHeight, maxSuggestionsHeight)

            // Update height constraint with animation
            UIView.animate(withDuration: 0.3) {
                self.suggestionsHeightConstraint?.constant = newHeight
                self.suggestionsTableView.isHidden = false
                self.view.layoutIfNeeded()
            }
        } else {
            UIView.animate(withDuration: 0.3) {
                self.suggestionsHeightConstraint?.constant = 0
                self.suggestionsTableView.isHidden = true
                self.view.layoutIfNeeded()
            }
        }
    }
}

extension UISearchViewController: UISearchBarDelegate {
    func searchBar(_ searchBar: UISearchBar, textDidChange searchText: String) {
        Task {
            await store.send(.generateSuggestion(searchText)).finish()
            suggestionsTableView.isHidden = store.suggestedTag.isEmpty
            suggestionsTableView.reloadData()
            updateSuggestionsVisibility(for: searchText)
        }
    }

    func searchBarSearchButtonClicked(_ searchBar: UISearchBar) {
        guard let searchText = searchBar.text, !searchText.isEmpty else { return }
        store.send(.searchSubmit(searchText))
        suggestionsTableView.isHidden = true
        searchBar.resignFirstResponder()
    }
}

extension UISearchViewController: UITableViewDelegate, UITableViewDataSource {
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return store.suggestedTag.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "SuggestionCell", for: indexPath)
        cell.textLabel?.text = store.suggestedTag[indexPath.row]
        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        let suggestion = store.suggestedTag[indexPath.row]
        let validKeyword = searchBar.text?.split(separator: " ").dropLast(1).joined(separator: " ") ?? ""
        searchBar.text = "\(validKeyword) \(suggestion)$,"
        UIView.animate(withDuration: 0.3) {
            self.suggestionsHeightConstraint?.constant = 0
            tableView.isHidden = true
            self.view.layoutIfNeeded()
        }
        tableView.deselectRow(at: indexPath, animated: true)
    }

}
