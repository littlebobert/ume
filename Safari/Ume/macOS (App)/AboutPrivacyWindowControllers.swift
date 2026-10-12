import AppKit

final class AboutWindowController: NSWindowController {
    init(openPrivacy: @escaping () -> Void) {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 310, height: 292), styleMask: [.titled, .closable, .fullSizeContentView], backing: .buffered, defer: false)
        window.title = "About Umete"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isReleasedWhenClosed = false
        window.center()

        let windowTitle = NSTextField(labelWithString: "About Umete")
        windowTitle.font = .systemFont(ofSize: 13, weight: .semibold)
        windowTitle.alignment = .center
        let icon = NSImageView(image: NSApp.applicationIconImage)
        icon.imageScaling = .scaleProportionallyUpOrDown
        icon.translatesAutoresizingMaskIntoConstraints = false
        let name = NSTextField(labelWithString: "Umete")
        name.font = .systemFont(ofSize: 26, weight: .bold)
        name.alignment = .center
        let version = NSTextField(labelWithString: "Version \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0")")
        version.textColor = .secondaryLabelColor
        let explanation = NSTextField(labelWithString: "Fills in web forms automatically.")
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
        let source = NSButton(title: "", target: LinkTarget.shared, action: #selector(LinkTarget.openSource))
        source.isBordered = false
        source.attributedTitle = NSAttributedString(
            string: "Open source under the MIT License",
            attributes: [
                .foregroundColor: NSColor.linkColor,
                .underlineStyle: NSUnderlineStyle.single.rawValue,
                .font: NSFont.systemFont(ofSize: NSFont.smallSystemFontSize)
            ]
        )

        let stack = NSStackView(views: [windowTitle, icon, name, version, explanation, madeInJapan, buttons, source])
        stack.orientation = .vertical
        stack.alignment = .centerX
        stack.spacing = 4
        stack.setCustomSpacing(18, after: windowTitle)
        stack.setCustomSpacing(7, after: version)
        stack.setCustomSpacing(6, after: explanation)
        stack.setCustomSpacing(6, after: madeInJapan)
        stack.setCustomSpacing(11, after: buttons)
        stack.edgeInsets = NSEdgeInsets(top: 7, left: 0, bottom: 10, right: 0)
        stack.translatesAutoresizingMaskIntoConstraints = false
        window.contentView?.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: window.contentView!.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: window.contentView!.trailingAnchor),
            stack.topAnchor.constraint(equalTo: window.contentView!.topAnchor),
            stack.bottomAnchor.constraint(equalTo: window.contentView!.bottomAnchor),
            icon.widthAnchor.constraint(equalToConstant: 78),
            icon.heightAnchor.constraint(equalToConstant: 78),
            explanation.widthAnchor.constraint(equalToConstant: 296)
        ])
        super.init(window: window)
    }

    required init?(coder: NSCoder) { nil }
}

final class PrivacyWindowController: NSWindowController {
    init() {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 560, height: 470), styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        window.title = "Umete Privacy"
        window.isReleasedWhenClosed = false
        window.minSize = NSSize(width: 500, height: 440)
        window.center()

        let title = NSTextField(labelWithString: "Privacy")
        title.font = .systemFont(ofSize: 24, weight: .bold)
        let intro = NSTextField(wrappingLabelWithString: "Umete keeps your answers encrypted, has no account, and collects no analytics.")
        intro.textColor = .secondaryLabelColor
        let details = [
            ("Encrypted answer storage", "Saved answers are encrypted with AES-GCM in Umete’s shared app container. The key is kept in Apple Keychain, and in your iCloud Keychain when sync is on."),
            ("Private iCloud sync", "With iCloud sync on, each answer is encrypted on this Mac before it goes to your private iCloud database, so Apple can’t read it. You can turn sync off in Settings → General."),
            ("AI receives field context, not answers", "For fields Umete can’t match itself, it sends only descriptions such as labels, field types, headings, and menu options, plus the labels of your saved answers. Saved values, values in the form, addresses, and contacts’ names stay on your Mac."),
            ("You stay in control", "You can edit or delete your saved answers at any time.")
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
        let policy = NSButton(title: "", target: LinkTarget.shared, action: #selector(LinkTarget.openPrivacyPolicy))
        policy.isBordered = false
        policy.attributedTitle = NSAttributedString(
            string: "Read the full privacy policy",
            attributes: [
                .foregroundColor: NSColor.linkColor,
                .underlineStyle: NSUnderlineStyle.single.rawValue,
                .font: NSFont.systemFont(ofSize: 12)
            ]
        )
        stack.addArrangedSubview(policy)
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
        NSWorkspace.shared.open(URL(string: "https://github.com/littlebobert/umete")!)
    }

    @objc func openPrivacyPolicy() {
        NSWorkspace.shared.open(URL(string: "https://umete.jp/privacy")!)
    }

    @objc func reportBug() {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown"
        let platform = "macOS \(ProcessInfo.processInfo.operatingSystemVersionString)"
        let body = SupportDiagnostics.bugReportBody(version: version, platform: platform)
        var components = URLComponents()
        components.scheme = "mailto"
        components.path = "justin.garcia@gmail.com"
        components.queryItems = [
            URLQueryItem(name: "subject", value: "Umete Bug Report"),
            URLQueryItem(name: "body", value: body)
        ]
        if let url = components.url { NSWorkspace.shared.open(url) }
    }
}
