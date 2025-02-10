import ComposableArchitecture
import SwiftUI
import UIKit

public struct UISearchView: UIViewControllerRepresentable {
    let store: StoreOf<SearchFeature>

    public init(store: StoreOf<SearchFeature>) {
        self.store = store
    }

    public func makeUIViewController(context: Context) -> UIViewController {
        UINavigationController(rootViewController: UISearchViewController(store: store))
    }

    public func updateUIViewController(
        _ uiViewController: UIViewController,
        context: Context
    ) {
        // Nothing to do
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
        searchBar.placeholder = "Search..."
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

    private func setupObserve() {
        observe { [weak self] in
            guard let self else { return }
            if store.archiveList.filter.filter?.isEmpty == false {
                self.view.layoutIfNeeded()
            }
        }
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        setupLayout()
        setupDelegates()
//        setupObserve()
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
