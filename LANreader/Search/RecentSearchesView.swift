import UIKit

final class RecentSearchesView: UIView {
    static let cellReuseIdentifier = "RecentSearchCell"

    var onSelect: ((String) -> Void)?
    var onDelete: ((String) -> Void)?
    var onClear: (() -> Void)?

    private(set) var searches = [String]()

    let tableView: UITableView = {
        let tableView = UITableView(frame: .zero, style: .insetGrouped)
        tableView.translatesAutoresizingMaskIntoConstraints = false
        tableView.keyboardDismissMode = .onDrag
        return tableView
    }()

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .systemGroupedBackground
        addSubview(tableView)
        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(equalTo: topAnchor),
            tableView.leadingAnchor.constraint(equalTo: leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
        tableView.dataSource = self
        tableView.delegate = self
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: Self.cellReuseIdentifier)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func update(searches: [String]) {
        guard self.searches != searches else { return }
        self.searches = searches
        tableView.reloadData()
    }

    private func makeHeaderView() -> UIView {
        var titleConfiguration = UIListContentConfiguration.prominentInsetGroupedHeader()
        titleConfiguration.text = String(localized: "search.recent.title")
        let titleView = UIListContentView(configuration: titleConfiguration)
        titleView.translatesAutoresizingMaskIntoConstraints = false

        let clearButton = UIButton(
            configuration: .plain(),
            primaryAction: UIAction(title: String(localized: "search.recent.clear")) { [weak self] _ in
                self?.onClear?()
            }
        )
        clearButton.translatesAutoresizingMaskIntoConstraints = false

        let header = UIView()
        header.addSubview(titleView)
        header.addSubview(clearButton)
        NSLayoutConstraint.activate([
            titleView.topAnchor.constraint(equalTo: header.topAnchor),
            titleView.leadingAnchor.constraint(equalTo: header.leadingAnchor),
            titleView.bottomAnchor.constraint(equalTo: header.bottomAnchor),
            clearButton.leadingAnchor.constraint(greaterThanOrEqualTo: titleView.trailingAnchor, constant: 8),
            clearButton.trailingAnchor.constraint(equalTo: header.layoutMarginsGuide.trailingAnchor),
            clearButton.centerYAnchor.constraint(equalTo: titleView.centerYAnchor)
        ])
        return header
    }
}

extension RecentSearchesView: UITableViewDataSource, UITableViewDelegate {
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        searches.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: Self.cellReuseIdentifier, for: indexPath)
        var configuration = cell.defaultContentConfiguration()
        configuration.text = searches[indexPath.row]
        configuration.textProperties.numberOfLines = 2
        configuration.image = UIImage(systemName: "clock.arrow.circlepath")
        configuration.imageProperties.tintColor = .secondaryLabel
        cell.contentConfiguration = configuration
        cell.accessibilityTraits = .button
        return cell
    }

    func tableView(_ tableView: UITableView, viewForHeaderInSection section: Int) -> UIView? {
        makeHeaderView()
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        onSelect?(searches[indexPath.row])
    }

    func tableView(
        _ tableView: UITableView,
        trailingSwipeActionsConfigurationForRowAt indexPath: IndexPath
    ) -> UISwipeActionsConfiguration? {
        let keyword = searches[indexPath.row]
        let delete = UIContextualAction(
            style: .destructive,
            title: String(localized: "delete")
        ) { [weak self] _, _, done in
            self?.delete(keyword)
            done(true)
        }
        return UISwipeActionsConfiguration(actions: [delete])
    }

    func tableView(
        _ tableView: UITableView,
        contextMenuConfigurationForRowAt indexPath: IndexPath,
        point: CGPoint
    ) -> UIContextMenuConfiguration? {
        let keyword = searches[indexPath.row]
        return UIContextMenuConfiguration(actionProvider: { [weak self] _ in
            UIMenu(children: [
                UIAction(
                    title: String(localized: "delete"),
                    image: UIImage(systemName: "trash"),
                    attributes: .destructive
                ) { _ in
                    self?.delete(keyword)
                }
            ])
        })
    }

    private func delete(_ keyword: String) {
        guard let row = searches.firstIndex(of: keyword) else { return }
        searches.remove(at: row)
        tableView.deleteRows(at: [IndexPath(row: row, section: 0)], with: .automatic)
        onDelete?(keyword)
    }
}
