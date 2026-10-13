import Combine
import SwiftUI

/// The iOS app: Umete's settings in standard controls, a tab bar of grouped forms
/// that follow the system text size. It reads and writes the same stores as the
/// Safari extension; the Mac app has its own AppKit settings.
struct SettingsView: View {
    @StateObject private var model = SettingsModel()

    var body: some View {
        TabView {
            GeneralTab()
                .tabItem { Label("General", systemImage: "gearshape") }
            AIMatchingTab()
                .tabItem { Label("AI Matching", systemImage: "sparkles") }
            SavedDataTab()
                .tabItem { Label("Saved Data", systemImage: "tray.full") }
            PrivacyTab()
                .tabItem { Label("Privacy", systemImage: "hand.raised") }
        }
        .environmentObject(model)
        .task { await model.load() }
        .onReceive(NotificationCenter.default.publisher(for: CloudSync.didApplyRemoteChanges)) { _ in
            Task { await model.load() }
        }
        .onReceive(NotificationCenter.default.publisher(for: CloudSync.didFinishSync)) { _ in
            Task { await model.load() }
        }
        .fullScreenCover(isPresented: $model.needsOnboarding) {
            OnboardingView().environmentObject(model)
        }
        .alert(model.alert?.title ?? "", isPresented: $model.showsAlert, presenting: model.alert) { _ in
            Button("OK", role: .cancel) {}
        } message: { alert in
            Text(alert.message)
        }
    }
}

// MARK: - Model

struct SavedAnswer: Identifiable {
    let id: String
    let label: String
    let value: String
}

enum AIProvider: String, CaseIterable, Identifiable {
    case umete, openai, anthropic
    case openAIDecisions = "openai-decisions"

    var id: String { rawValue }

    var name: String {
        switch self {
        case .umete: return "Umete (free)"
        case .openai: return "OpenAI"
        case .anthropic: return "Anthropic"
        case .openAIDecisions: return "OpenAI Decisions (your key)"
        }
    }

    var defaultModel: String {
        switch self {
        case .umete: return ""
        case .openai: return "gpt-5.6-sol"
        case .anthropic: return "claude-opus-5"
        case .openAIDecisions: return "gpt-6-luna"
        }
    }

    var needsKey: Bool { SafariWebExtensionHandlerProviders.requiresKey(rawValue) }
}

@MainActor
final class SettingsModel: ObservableObject {
    struct Alert {
        let title: String
        let message: String
    }

    @Published var provider: AIProvider = .umete
    @Published var modelName = ""
    @Published var apiKeyDraft = ""
    @Published private(set) var hasKey = false
    @Published private(set) var answers: [SavedAnswer] = []
    @Published var syncEnabled = CloudSync.isEnabled
    @Published private(set) var syncStatus = "Checking iCloud…"
    @Published private(set) var isSyncing = false
    @Published var needsOnboarding = false
    @Published var showsAlert = false
    private(set) var alert: Alert?

    func load() async {
        let settings = SettingsStore.load()
        provider = AIProvider(rawValue: settings?.provider ?? "") ?? .umete
        modelName = settings?.model.isEmpty == false ? settings!.model : provider.defaultModel
        hasKey = !(settings?.apiKey.isEmpty ?? true)
        needsOnboarding = !OnboardingStore.isComplete
        answers = ((try? AnswerStore.load()) ?? []).enumerated().map { index, answer in
            SavedAnswer(
                id: answer["answerID"] as? String ?? "answer-\(index)",
                label: Self.label(of: answer, index: index),
                value: Self.valueText(of: answer, label: Self.label(of: answer, index: index))
            )
        }
        syncEnabled = CloudSync.isEnabled
        syncStatus = await CloudSync.shared.statusDescription()
    }

    func chooseProvider(_ newValue: AIProvider) {
        if modelName.isEmpty || AIProvider.allCases.contains(where: { $0.defaultModel == modelName }) {
            modelName = newValue.defaultModel
        }
        provider = newValue
        // The free service needs nothing else, so it applies at once, like a setting
        // in Settings; providers with a key wait for Save.
        if !newValue.needsKey && !needsOnboarding {
            Task { await saveSettings(quietly: true) }
        }
    }

    /// Saves the provider, model, and (when typed) a new key. Returns whether it saved.
    @discardableResult
    func saveSettings(completingOnboarding: Bool = false, quietly: Bool = false) async -> Bool {
        let model = modelName.trimmingCharacters(in: .whitespacesAndNewlines)
        let typedKey = apiKeyDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        let key = typedKey.isEmpty ? SettingsStore.load()?.apiKey ?? "" : typedKey
        guard !provider.needsKey || (!model.isEmpty && !key.isEmpty) else {
            show("Missing Details", "Enter a model and an API key for \(provider.name), or choose Umete (free).")
            return false
        }
        do {
            // The free service ignores the model; any saved key is kept for switching back.
            try SettingsStore.save(AISettings(provider: provider.rawValue, model: provider.needsKey ? model : "", apiKey: key))
            if completingOnboarding { OnboardingStore.isComplete = true }
            apiKeyDraft = ""
            await load()
            if !completingOnboarding && !quietly { show("Saved", "Your AI settings are stored securely in Apple Keychain.") }
            return true
        } catch {
            show("Couldn’t Save", error.localizedDescription)
            return false
        }
    }

    func deleteKey() async {
        SettingsStore.delete()
        await load()
        show("Key Deleted", "The saved API key was deleted.")
    }

    func delete(at offsets: IndexSet) async {
        do {
            for index in offsets { try AnswerStore.delete(id: answers[index].id) }
        } catch {
            show("Couldn’t Delete", "Umete could not delete that answer.")
        }
        await load()
    }

    func clearAnswers() async {
        do {
            try AnswerStore.clear()
            show("Answers Deleted", CloudSync.isEnabled
                ? "All saved answers were deleted from this device and will be removed from your other devices. Your AI settings were kept."
                : "All saved answers were deleted. Your AI settings were kept.")
        } catch {
            show("Couldn’t Delete", "Umete could not delete all saved answers.")
        }
        await load()
    }

    func setSyncEnabled(_ enabled: Bool) async {
        CloudSync.isEnabled = enabled
        syncEnabled = enabled
        if enabled { await syncNow() } else { await load() }
    }

    func syncNow() async {
        isSyncing = true
        syncStatus = "Syncing…"
        do {
            _ = try await CloudSync.shared.sync(reason: .manual)
        } catch {
            // The status below explains what went wrong, such as no iCloud account.
        }
        isSyncing = false
        await load()
    }

    private func show(_ title: String, _ message: String) {
        alert = Alert(title: title, message: message)
        showsAlert = true
    }

    private static func label(of answer: [String: Any], index: Int) -> String {
        for key in ["accessibleName", "label", "placeholder", "name", "autocomplete"] {
            if let text = answer[key] as? String, !text.isEmpty { return text }
        }
        return "Saved answer \(index + 1)"
    }

    private static func valueText(of answer: [String: Any], label: String) -> String {
        switch answer["value"] {
        case let flag as Bool:
            return flag ? "Yes" : "No"
        case let parts as [String: Any]:
            let isAddress = answer["answerType"] as? String == "address"
            let keys = isAddress
                ? ["addressLine1", "addressLine2", "locality", "administrativeArea", "postalCode", "countryName"]
                : ["name", "role", "phone"]
            // A contact's label is usually its name already; don't say it twice.
            return keys.compactMap { parts[$0] as? String }
                .filter { !$0.isEmpty && !(!isAddress && $0 == label) }
                .joined(separator: isAddress ? ", " : " · ")
        case let text as String:
            return text
        case let number as NSNumber:
            return number.stringValue
        default:
            return ""
        }
    }
}

// MARK: - Shared pieces

/// The app's icon, sized with the text so it grows with larger text sizes.
struct AppIconImage: View {
    @ScaledMetric private var size: CGFloat
    init(size: CGFloat) { _size = ScaledMetric(wrappedValue: size, relativeTo: .title) }

    var body: some View {
        Image("LargeIcon")
            .resizable()
            .frame(width: size, height: size)
            .clipShape(RoundedRectangle(cornerRadius: size * 0.225, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: size * 0.225, style: .continuous).stroke(Color.primary.opacity(0.08)))
            .accessibilityHidden(true)
    }
}

/// The provider, model, and key fields, shared by onboarding and the AI tab.
struct ProviderFields: View {
    @EnvironmentObject private var model: SettingsModel

    var body: some View {
        Picker("Provider", selection: Binding(get: { model.provider }, set: { model.chooseProvider($0) })) {
            ForEach(AIProvider.allCases) { Text($0.name).tag($0) }
        }
        if model.provider.needsKey {
            TextField("Model", text: $model.modelName)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            SecureField(model.hasKey ? "API key (saved)" : "API key", text: $model.apiKeyDraft)
                .textContentType(.password)
        }
    }
}

// MARK: - Tabs

struct GeneralTab: View {
    @EnvironmentObject private var model: SettingsModel
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        NavigationView {
            Form {
                Section {
                    // The icon beside the name, or above it at accessibility text sizes.
                    if typeSize.isAccessibilitySize {
                        VStack(alignment: .leading, spacing: 8) { AppIconImage(size: 60); identity }
                            .padding(.vertical, 4)
                    } else {
                        HStack(spacing: 14) { AppIconImage(size: 60); identity }
                            .padding(.vertical, 4)
                    }
                }
                Section {
                    Text("Turn on Umete in Settings → Apps → Safari → Extensions, then open it from Safari’s page menu on a form.")
                } header: {
                    Text("Safari Extension")
                }
                Section {
                    Toggle("Sync with iCloud", isOn: Binding(get: { model.syncEnabled }, set: { enabled in
                        Task { await model.setSyncEnabled(enabled) }
                    }))
                    Button {
                        Task { await model.syncNow() }
                    } label: {
                        HStack {
                            Text("Sync Now")
                            if model.isSyncing { Spacer(); ProgressView() }
                        }
                    }
                    .disabled(!model.syncEnabled || model.isSyncing)
                } header: {
                    Text("iCloud")
                } footer: {
                    Text("\(model.syncStatus) Answers are encrypted on your devices with a key in your iCloud Keychain, so Apple can’t read them.")
                }
                Section {
                    Text("Umete matches fields on your device first. AI matching is used only for fields it can’t match itself.")
                } header: {
                    Text("How Umete Fills Forms")
                }
            }
            .navigationTitle("General")
        }
        .navigationViewStyle(.stack)
    }

    private var identity: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Umete").font(.title2.weight(.semibold))
            Text("Fills in web forms in Safari, with answers you’ve saved.")
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
    }
}

struct AIMatchingTab: View {
    @EnvironmentObject private var model: SettingsModel
    @State private var confirmsKeyDeletion = false

    var body: some View {
        NavigationView {
            Form {
                Section {
                    ProviderFields()
                } footer: {
                    Text(model.provider.needsKey
                        ? "Your key is stored in Apple Keychain on this device. It isn’t synced."
                        : "Free, with a daily limit. No key needed.")
                }
                if model.provider.needsKey {
                    Section {
                        Button("Save") { Task { await model.saveSettings() } }
                    }
                }
                if model.hasKey {
                    Section {
                        Button("Delete Saved Key", role: .destructive) { confirmsKeyDeletion = true }
                    }
                }
            }
            .navigationTitle("AI Matching")
            .confirmationDialog("Delete the saved API key?", isPresented: $confirmsKeyDeletion, titleVisibility: .visible) {
                Button("Delete Key", role: .destructive) { Task { await model.deleteKey() } }
            }
        }
        .navigationViewStyle(.stack)
    }
}

struct SavedDataTab: View {
    @EnvironmentObject private var model: SettingsModel
    @State private var confirmsClear = false

    var body: some View {
        NavigationView {
            List {
                Section {
                    if model.answers.isEmpty {
                        Text("Use Remember my answers on a completed form in Safari to see answers here.")
                            .foregroundColor(.secondary)
                    }
                    ForEach(model.answers) { answer in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(answer.label).font(.subheadline).foregroundColor(.secondary)
                            Text(answer.value)
                        }
                        .padding(.vertical, 2)
                        .accessibilityElement(children: .combine)
                    }
                    .onDelete { offsets in Task { await model.delete(at: offsets) } }
                } footer: {
                    if !model.answers.isEmpty {
                        Text(model.answers.count == 1 ? "1 saved answer, encrypted." : "\(model.answers.count) saved answers, encrypted.")
                    }
                }
                if !model.answers.isEmpty {
                    Section {
                        Button("Clear All Answers…", role: .destructive) { confirmsClear = true }
                    } footer: {
                        Text("Deletes every saved answer and keeps your AI settings.")
                    }
                }
            }
            .navigationTitle("Saved Data")
            .refreshable { await model.load() }
            .confirmationDialog(
                model.syncEnabled ? "Delete every saved answer on all your devices?" : "Delete every saved answer on this device?",
                isPresented: $confirmsClear,
                titleVisibility: .visible
            ) {
                Button("Delete All Answers", role: .destructive) { Task { await model.clearAnswers() } }
            } message: {
                Text("Your AI settings and API key are kept. This can’t be undone.")
            }
        }
        .navigationViewStyle(.stack)
    }
}

struct PrivacyTab: View {
    private let points: [(String, String, String)] = [
        ("lock", "Answers are encrypted", "Saved answers are encrypted with AES-GCM in Umete’s app storage. The key is kept in Apple Keychain, and in your iCloud Keychain when sync is on."),
        ("icloud", "iCloud sync stays private", "With Sync with iCloud on, each answer is encrypted on this device before it goes to your private iCloud database, so Apple can’t read it. You can turn sync off on the General tab."),
        ("sparkles", "Answer values are never sent to AI", "For fields Umete can’t match itself, it sends only descriptions such as labels, field types, headings, and menu options, plus the labels of your saved answers. Saved values, values in the form, addresses, and contacts’ names stay on your device."),
        ("eye.slash", "Sensitive fields are skipped", "Umete does not save passwords, payment fields, hidden values, or fields identified as security secrets."),
        ("chart.bar.xaxis", "No analytics", "Umete has no account and collects no analytics."),
    ]

    var body: some View {
        NavigationView {
            List {
                Section {
                    ForEach(points, id: \.1) { icon, title, detail in
                        Label {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(title).font(.headline)
                                Text(detail).font(.subheadline).foregroundColor(.secondary)
                            }
                            .padding(.vertical, 4)
                        } icon: {
                            Image(systemName: icon).foregroundColor(.accentColor)
                        }
                        .accessibilityElement(children: .combine)
                    }
                }
                Section {
                    Link("Privacy Policy", destination: URL(string: "https://umete.jp/privacy")!)
                }
            }
            .navigationTitle("Privacy")
        }
        .navigationViewStyle(.stack)
    }
}

// MARK: - Onboarding

struct OnboardingView: View {
    @EnvironmentObject private var model: SettingsModel

    var body: some View {
        NavigationView {
            Form {
                Section {
                    VStack(spacing: 12) {
                        AppIconImage(size: 88)
                        Text("Welcome to Umete").font(.title.weight(.bold)).multilineTextAlignment(.center)
                        Text("Umete remembers answers you choose and fills similar web forms in Safari. It matches on your device first and uses AI only when needed.")
                            .multilineTextAlignment(.center)
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .listRowBackground(Color.clear)
                }
                Section {
                    ProviderFields()
                } header: {
                    Text("AI Matching")
                } footer: {
                    Text("Umete (free) works without a key, with a daily limit. Keys you add are stored in Apple Keychain. Saved answer values are never sent for AI matching.")
                }
                Section {
                    Button {
                        Task { await model.saveSettings(completingOnboarding: true) }
                    } label: {
                        Text("Continue").font(.headline).frame(maxWidth: .infinity)
                    }
                }
            }
            .navigationBarHidden(true)
        }
        .navigationViewStyle(.stack)
        .interactiveDismissDisabled()
    }
}
