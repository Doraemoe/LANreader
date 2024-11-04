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
        tableView.layer.borderColor = UIColor.systemGray5.cgColor
        return tableView
    }()

    private func setupLayout() {
        view.addSubview(searchBar)
        view.addSubview(suggestionsTableView)

        let archiveListView = UIArchiveListViewController(
            store: store.scope(state: \.archiveList, action: \.archiveList)
        )
        add(archiveListView)

        NSLayoutConstraint.activate([
            // Search bar constraints
            searchBar.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            searchBar.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 8),
            searchBar.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -8),

            suggestionsTableView.topAnchor.constraint(equalTo: searchBar.bottomAnchor, constant: 8),
            suggestionsTableView.leadingAnchor.constraint(equalTo: searchBar.leadingAnchor),
            suggestionsTableView.trailingAnchor.constraint(equalTo: searchBar.trailingAnchor),
            suggestionsTableView.heightAnchor.constraint(lessThanOrEqualToConstant: 200),

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
    }
}

extension UISearchViewController: UISearchBarDelegate {
}

extension UISearchViewController: UITableViewDelegate, UITableViewDataSource {
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return 0
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "SuggestionCell", for: indexPath)
        cell.textLabel?.text = "TODO"
        return cell
    }

}
