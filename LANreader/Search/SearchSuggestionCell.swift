import UIKit

final class SearchSuggestionCell: UITableViewCell {
    static let reuseIdentifier = "SearchSuggestionCell"

    private let iconContainer = UIView()
    private let iconImageView = UIImageView()
    private let tagLabel = UILabel()
    private let chevronImageView = UIImageView(image: UIImage(systemName: "chevron.forward"))
    private let separatorView = UIView()

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        setupLayout()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(with tag: TagWithType, isLast: Bool) {
        let tintColor: UIColor = tag.type == .popular ? .systemOrange : .systemBlue
        let symbolName = tag.type == .popular ? "flame.fill" : "tag.fill"

        tagLabel.text = tag.tag
        iconImageView.image = UIImage(systemName: symbolName)
        iconImageView.tintColor = tintColor
        iconContainer.backgroundColor = tintColor.withAlphaComponent(0.14)
        separatorView.isHidden = isLast
        accessibilityLabel = tag.tag
    }

    private func setupLayout() {
        backgroundColor = .clear
        contentView.backgroundColor = .clear
        selectionStyle = .default
        accessibilityTraits = .button

        let selectedView = UIView()
        selectedView.backgroundColor = .tertiarySystemFill
        selectedBackgroundView = selectedView

        iconContainer.translatesAutoresizingMaskIntoConstraints = false
        iconContainer.layer.cornerRadius = 17
        iconContainer.clipsToBounds = true

        iconImageView.translatesAutoresizingMaskIntoConstraints = false
        iconImageView.contentMode = .scaleAspectFit
        iconImageView.preferredSymbolConfiguration = UIImage.SymbolConfiguration(pointSize: 15, weight: .semibold)

        tagLabel.translatesAutoresizingMaskIntoConstraints = false
        tagLabel.font = .preferredFont(forTextStyle: .body)
        tagLabel.adjustsFontForContentSizeCategory = true
        tagLabel.textColor = .label
        tagLabel.lineBreakMode = .byTruncatingTail

        chevronImageView.translatesAutoresizingMaskIntoConstraints = false
        chevronImageView.tintColor = .tertiaryLabel
        chevronImageView.preferredSymbolConfiguration = UIImage.SymbolConfiguration(pointSize: 12, weight: .bold)

        separatorView.translatesAutoresizingMaskIntoConstraints = false
        separatorView.backgroundColor = .separator.withAlphaComponent(0.45)

        contentView.addSubview(iconContainer)
        iconContainer.addSubview(iconImageView)
        contentView.addSubview(tagLabel)
        contentView.addSubview(chevronImageView)
        contentView.addSubview(separatorView)

        NSLayoutConstraint.activate([
            iconContainer.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 14),
            iconContainer.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            iconContainer.widthAnchor.constraint(equalToConstant: 34),
            iconContainer.heightAnchor.constraint(equalTo: iconContainer.widthAnchor),

            iconImageView.centerXAnchor.constraint(equalTo: iconContainer.centerXAnchor),
            iconImageView.centerYAnchor.constraint(equalTo: iconContainer.centerYAnchor),

            tagLabel.leadingAnchor.constraint(equalTo: iconContainer.trailingAnchor, constant: 12),
            tagLabel.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            tagLabel.trailingAnchor.constraint(equalTo: chevronImageView.leadingAnchor, constant: -10),

            chevronImageView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            chevronImageView.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),

            separatorView.leadingAnchor.constraint(equalTo: tagLabel.leadingAnchor),
            separatorView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -14),
            separatorView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
            separatorView.heightAnchor.constraint(equalToConstant: 1.0 / UIScreen.main.scale)
        ])
    }
}
