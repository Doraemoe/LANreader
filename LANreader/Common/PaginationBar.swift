import UIKit

/// Floating archive pager. Tapping its position opens direct page entry.
final class PaginationBar: UIView {
    private var onSelectPage: ((Int) -> Void)?
    private var onRequestPageInput: (() -> Void)?
    private var currentPage = 0
    private var pageCount = 0

    private let background: UIVisualEffectView = {
        if #available(iOS 26.0, *) {
            let glass = UIGlassEffect(style: .regular)
            glass.isInteractive = true
            let view = UIVisualEffectView(effect: glass)
            view.cornerConfiguration = .capsule()
            return view
        }
        let view = UIVisualEffectView(effect: UIBlurEffect(style: .systemThinMaterial))
        view.clipsToBounds = true
        return view
    }()

    private let stackView: UIStackView = {
        let stack = UIStackView()
        stack.axis = .horizontal
        stack.alignment = .center
        stack.distribution = .fill
        stack.spacing = 2
        return stack
    }()

    private let previousButton = UIButton(configuration: .plain())
    private let positionButton = UIButton(configuration: .plain())
    private let nextButton = UIButton(configuration: .plain())

    override init(frame: CGRect) {
        super.init(frame: frame)

        layer.shadowColor = UIColor.black.cgColor
        layer.shadowOpacity = 0.18
        layer.shadowRadius = 8
        layer.shadowOffset = CGSize(width: 0, height: 2)

        addSubview(background)
        background.contentView.addSubview(stackView)
        background.translatesAutoresizingMaskIntoConstraints = false
        stackView.translatesAutoresizingMaskIntoConstraints = false

        NSLayoutConstraint.activate([
            background.topAnchor.constraint(equalTo: topAnchor),
            background.bottomAnchor.constraint(equalTo: bottomAnchor),
            background.leadingAnchor.constraint(equalTo: leadingAnchor),
            background.trailingAnchor.constraint(equalTo: trailingAnchor),
            stackView.topAnchor.constraint(equalTo: background.contentView.topAnchor, constant: 4),
            stackView.bottomAnchor.constraint(equalTo: background.contentView.bottomAnchor, constant: -4),
            stackView.leadingAnchor.constraint(equalTo: background.contentView.leadingAnchor, constant: 6),
            stackView.trailingAnchor.constraint(equalTo: background.contentView.trailingAnchor, constant: -6)
        ])

        setupButtons()
        registerForTraitChanges([UITraitPreferredContentSizeCategory.self]) { (bar: Self, _) in
            bar.render()
        }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        if #unavailable(iOS 26.0) {
            background.layer.cornerRadius = bounds.height / 2
        }
    }

    func configure(
        currentPage: Int,
        pageCount: Int,
        onSelectPage: @escaping (Int) -> Void,
        onRequestPageInput: @escaping () -> Void
    ) {
        self.onSelectPage = onSelectPage
        self.onRequestPageInput = onRequestPageInput
        self.pageCount = pageCount
        self.currentPage = PaginationPositioning.clampedPage(currentPage, pageCount: pageCount)
        render()
    }

    private func setupButtons() {
        let symbol = UIImage.SymbolConfiguration(textStyle: .headline, scale: .large)
        previousButton.configuration?.image = UIImage(
            systemName: "chevron.left",
            withConfiguration: symbol
        )
        nextButton.configuration?.image = UIImage(
            systemName: "chevron.right",
            withConfiguration: symbol
        )

        previousButton.addAction(
            UIAction { [weak self] _ in self?.step(-1) },
            for: .touchUpInside
        )

        nextButton.addAction(
            UIAction { [weak self] _ in self?.step(1) },
            for: .touchUpInside
        )

        positionButton.accessibilityHint = String(localized: "archive.list.page.jump.title")
        positionButton.addAction(
            UIAction { [weak self] _ in self?.onRequestPageInput?() },
            for: .touchUpInside
        )

        [previousButton, nextButton].forEach { button in
            // The glass capsule carries the affordance, so the arrows stay monochrome and
            // lean on a deliberately faint disabled colour to mark the first and last page.
            button.configurationUpdateHandler = { button in
                button.configuration?.baseForegroundColor = button.isEnabled ? .label : .quaternaryLabel
            }
        }

        [previousButton, positionButton, nextButton].forEach { button in
            button.translatesAutoresizingMaskIntoConstraints = false
            stackView.addArrangedSubview(button)
            button.heightAnchor.constraint(greaterThanOrEqualToConstant: 44).isActive = true
        }
        [previousButton, nextButton].forEach { button in
            button.widthAnchor.constraint(greaterThanOrEqualToConstant: 44).isActive = true
        }
    }

    private func step(_ offset: Int) {
        onSelectPage?(currentPage + offset)
    }

    private func render() {
        guard pageCount > 1 else { return }

        previousButton.isEnabled = currentPage > 0
        nextButton.isEnabled = currentPage < pageCount - 1
        positionButton.configuration?.attributedTitle = AttributedString(
            position(
                String(
                    format: String(localized: "archive.list.page.position %1$lld %2$lld"),
                    Int64(currentPage + 1), Int64(pageCount)
                )
            )
        )
    }

    /// Gives the current page the visual weight and demotes the total to supporting text.
    private func position(_ text: String) -> NSAttributedString {
        let attributed = NSMutableAttributedString(
            string: text,
            attributes: [
                .font: UIFont.preferredFont(forTextStyle: .subheadline),
                .foregroundColor: UIColor.secondaryLabel
            ]
        )

        let range = (text as NSString).range(of: String(currentPage + 1))
        if range.location != NSNotFound {
            attributed.addAttributes(
                [.font: pageFont, .foregroundColor: UIColor.label],
                range: range
            )
        }
        return attributed
    }

    /// Rounded, monospaced digits so the capsule keeps its width as the page changes.
    private var pageFont: UIFont {
        let size = UIFont.preferredFont(forTextStyle: .title3).pointSize
        var descriptor = UIFont.systemFont(ofSize: size, weight: .semibold).fontDescriptor
        descriptor = descriptor.withDesign(.rounded) ?? descriptor
        descriptor = descriptor.addingAttributes([
            .featureSettings: [[
                UIFontDescriptor.FeatureKey.type: kNumberSpacingType,
                UIFontDescriptor.FeatureKey.selector: kMonospacedNumbersSelector
            ]]
        ])
        return UIFont(descriptor: descriptor, size: 0)
    }
}
