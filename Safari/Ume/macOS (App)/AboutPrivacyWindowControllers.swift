import AppKit

final class AboutWindowController: NSWindowController {
    init(openPrivacy: @escaping () -> Void) {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 430, height: 440), styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.title = "About Ume"
        window.isReleasedWhenClosed = false
        window.center()

        let icon = NSImageView(image: NSApp.applicationIconImage)
        icon.imageScaling = .scaleProportionallyUpOrDown
        icon.translatesAutoresizingMaskIntoConstraints = false
        let name = NSTextField(labelWithString: "Ume")
        name.font = .systemFont(ofSize: 26, weight: .bold)
        let version = NSTextField(labelWithString: "Version \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0") (\(Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"))")
        version.textColor = .secondaryLabelColor
        let explanation = NSTextField(labelWithString: "Fill it once. Keep it private.")
        explanation.textColor = .secondaryLabelColor
        explanation.alignment = .center
        let madeInJapan = NSTextField(labelWithString: "Made in Japan")
        madeInJapan.alignment = .center
        let reportBug = NSButton(title: "Report a Bug…", target: LinkTarget.shared, action: #selector(LinkTarget.reportBug))
        reportBug.bezelStyle = .rounded
        let privacy = ClosureButton(title: "Privacy…", action: openPrivacy)
        privacy.bezelStyle = .rounded
        let buttons = NSStackView(views: [reportBug, privacy])
        buttons.orientation = .horizontal
        buttons.alignment = .centerY
        buttons.spacing = 8
        let source = NSButton(title: "Open source under the MIT License", target: LinkTarget.shared, action: #selector(LinkTarget.openSource))
        source.bezelStyle = .inline
        source.contentTintColor = .linkColor

        let stack = NSStackView(views: [icon, name, version, explanation, madeInJapan, buttons, source])
        stack.orientation = .vertical
        stack.alignment = .centerX
        stack.spacing = 9
        stack.setCustomSpacing(18, after: version)
        stack.setCustomSpacing(14, after: explanation)
        stack.setCustomSpacing(14, after: madeInJapan)
        stack.setCustomSpacing(20, after: buttons)
        stack.edgeInsets = NSEdgeInsets(top: 28, left: 34, bottom: 26, right: 34)
        stack.translatesAutoresizingMaskIntoConstraints = false
        window.contentView?.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: window.contentView!.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: window.contentView!.trailingAnchor),
            stack.topAnchor.constraint(equalTo: window.contentView!.topAnchor),
            stack.bottomAnchor.constraint(equalTo: window.contentView!.bottomAnchor),
            icon.widthAnchor.constraint(equalToConstant: 88),
            icon.heightAnchor.constraint(equalToConstant: 88),
            explanation.widthAnchor.constraint(equalToConstant: 360)
        ])
        super.init(window: window)
    }

    required init?(coder: NSCoder) { nil }
}

final class PrivacyWindowController: NSWindowController {
    init() {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 560, height: 430), styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        window.title = "Ume Privacy"
        window.isReleasedWhenClosed = false
        window.minSize = NSSize(width: 500, height: 380)
        window.center()

        let title = NSTextField(labelWithString: "Privacy")
        title.font = .systemFont(ofSize: 24, weight: .bold)
        let intro = NSTextField(wrappingLabelWithString: "Ume is designed to keep your actual answers on your device.")
        intro.textColor = .secondaryLabelColor
        let details = [
            ("Encrypted local storage", "Saved values are encrypted in Ume’s shared app container. The encryption key is protected by Apple Keychain."),
            ("AI receives field context, not answers", "For unmatched fields, Ume may send bounded labels, descriptions, field types, group headings, and option labels. Saved answer values remain local."),
            ("Sensitive fields are skipped", "Ume does not save passwords, payment fields, hidden values, or fields identified as security secrets."),
            ("You stay in control", "You can edit or delete individual saved answers, or clear all answers while keeping your provider settings and API key.")
        ]
        let stack = NSStackView(views: [title, intro])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 9
        for detail in details {
            let heading = NSTextField(labelWithString: detail.0)
            heading.font = .systemFont(ofSize: 13, weight: .semibold)
            let copy = NSTextField(wrappingLabelWithString: detail.1)
            copy.textColor = .secondaryLabelColor
            copy.font = .systemFont(ofSize: 12)
            stack.addArrangedSubview(heading)
            stack.addArrangedSubview(copy)
            copy.widthAnchor.constraint(equalToConstant: 480).isActive = true
            stack.setCustomSpacing(18, after: copy)
        }
        stack.edgeInsets = NSEdgeInsets(top: 28, left: 32, bottom: 28, right: 32)
        stack.translatesAutoresizingMaskIntoConstraints = false
        window.contentView?.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: window.contentView!.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: window.contentView!.trailingAnchor),
            stack.topAnchor.constraint(equalTo: window.contentView!.topAnchor)
        ])
        super.init(window: window)
    }

    required init?(coder: NSCoder) { nil }
}

private final class ClosureButton: NSButton {
    private let handler: () -> Void
    init(title: String, action: @escaping () -> Void) {
        handler = action
        super.init(frame: .zero)
        self.title = title
        target = self
        self.action = #selector(invoke)
    }
    required init?(coder: NSCoder) { nil }
    @objc private func invoke() { handler() }
}

private final class LinkTarget: NSObject {
    static let shared = LinkTarget()
    @objc func openSource() {
        NSWorkspace.shared.open(URL(string: "https://github.com/littlebobert/ume")!)
    }

    @objc func reportBug() {
        var components = URLComponents()
        components.scheme = "mailto"
        components.path = "justin.garcia@gmail.com"
        components.queryItems = [URLQueryItem(name: "subject", value: "Ume Bug Report")]
        if let url = components.url { NSWorkspace.shared.open(url) }
    }
}
