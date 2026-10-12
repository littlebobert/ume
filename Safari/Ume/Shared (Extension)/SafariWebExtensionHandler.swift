import SafariServices
import Security
import CryptoKit
#if os(macOS)
import AppKit
#endif

private enum MappingError: LocalizedError {
    case message(String)
    var errorDescription: String? {
        switch self { case .message(let value): return value }
    }
}

class SafariWebExtensionHandler: NSObject, NSExtensionRequestHandling {
    func beginRequest(with context: NSExtensionContext) {
        let request = context.inputItems.first as? NSExtensionItem
        let message: Any?
        if #available(iOS 15.0, macOS 11.0, *) {
            message = request?.userInfo?[SFExtensionMessageKey]
        } else {
            message = request?.userInfo?["message"]
        }

        guard let payload = message as? [String: Any], let type = payload["type"] as? String else {
            complete(context, ["ok": false, "error": "Unsupported native message."])
            return
        }

        switch type {
        case "UME_GET_ONBOARDING_STATE":
            complete(context, ["ok": true, "complete": OnboardingStore.isComplete])
        case "UME_GET_DEBUG_LOGGING_STATE":
            complete(context, ["ok": true, "enabled": AIDebugLogStore.isEnabled])
        case "UME_OPEN_APP", "UME_OPEN_SETTINGS":
            let destination = type == "UME_OPEN_SETTINGS" ? "settings" : "onboarding"
            guard let url = URL(string: "ume://\(destination)") else {
                complete(context, ["ok": false, "error": "Umete could not open the companion app."])
                return
            }
            #if os(macOS)
            openContainingApp(url, from: context)
            #else
            context.open(url) { [weak self] opened in
                self?.complete(context, opened
                    ? ["ok": true]
                    : ["ok": false, "error": "Umete Settings could not be opened."])
            }
            #endif
        case "UME_GET_ANSWERS":
            Task {
                // Pick up changes from other devices first, but never make the popup wait long.
                _ = await CloudSync.shared.sync(reason: .extensionRead, timeout: 3, pullMinimumInterval: 20)
                do {
                    complete(context, ["ok": true, "answers": try AnswerStore.load()])
                } catch {
                    complete(context, ["ok": false, "error": error.localizedDescription])
                }
            }
        case "UME_SAVE_ANSWERS":
            do {
                let answers = payload["answers"] as? [[String: Any]] ?? []
                try AnswerStore.save(answers)
            } catch {
                complete(context, ["ok": false, "error": error.localizedDescription])
                return
            }
            Task {
                // Upload before replying; the extension process may not outlive the request.
                _ = await CloudSync.shared.sync(reason: .extensionWrite, timeout: 5)
                complete(context, ["ok": true])
            }
        case "UME_MAP_FIELDS":
            Task {
                do {
                    let mappings = try await mapFields(payload)
                    complete(context, ["ok": true, "mappings": mappings])
                } catch {
                    complete(context, ["ok": false, "error": error.localizedDescription])
                }
            }
        default:
            complete(context, ["ok": false, "error": "Unsupported native message."])
        }
    }

    #if os(macOS)
    private func openContainingApp(_ url: URL, from context: NSExtensionContext) {
        let appURL = Bundle.main.bundleURL
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()

        guard appURL.pathExtension == "app" else {
            complete(context, ["ok": false, "error": "Umete Settings could not be opened."])
            return
        }

        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        NSWorkspace.shared.open([url], withApplicationAt: appURL, configuration: configuration) { [weak self] app, _ in
            self?.complete(context, app != nil
                ? ["ok": true]
                : ["ok": false, "error": "Umete Settings could not be opened."])
        }
    }
    #endif

    private static let schemaKeys: Set<String> = [
        "accessibleDescription", "accessibleName", "answerType", "autocomplete", "form", "group",
        "groupName", "id", "inputType", "kind", "label", "name", "options", "placeholder",
        "required", "section", "tableHeaders", "userLabel"
    ]

    private static func sanitizedSchema(_ source: [String: Any], identityKey: String) -> [String: Any]? {
        guard let identity = source[identityKey] as? String, !identity.isEmpty else { return nil }
        var result: [String: Any] = [identityKey: identity]
        for key in schemaKeys where source[key] != nil { result[key] = source[key] }
        return result
    }

    private func mapFields(_ payload: [String: Any]) async throws -> [[String: String]] {
        let settings = SettingsStore.load() ?? AISettings(provider: SafariWebExtensionHandlerProviders.default, model: "", apiKey: "")
        guard Self.supportedProviders.contains(settings.provider),
              !SafariWebExtensionHandlerProviders.requiresKey(settings.provider) || !settings.apiKey.isEmpty else {
            throw MappingError.message("Open the Umete app and add an API key, or switch AI matching to Umete (free).")
        }
        guard let rawSaved = payload["saved"] as? [[String: Any]],
              let rawFields = payload["fields"] as? [[String: Any]],
              rawSaved.count <= 200, rawFields.count <= 200 else {
            throw MappingError.message("The form mapping request was invalid or too large.")
        }
        let saved = rawSaved
            .filter { ($0["answerType"] as? String) != "address" }
            .compactMap { Self.sanitizedSchema($0, identityKey: "key") }
        let fields = rawFields.compactMap { Self.sanitizedSchema($0, identityKey: "field") }

        let savedIDs = Set(saved.compactMap { $0["key"] as? String })
        let fieldIDs = Set(fields.compactMap { $0["field"] as? String })
        let input: [String: Any] = ["savedFieldSchemas": saved, "currentFormSchemas": fields]
        let inputData = try JSONSerialization.data(withJSONObject: input, options: [.sortedKeys])
        guard let inputJSON = String(data: inputData, encoding: .utf8) else {
            throw MappingError.message("Could not encode sanitized field schemas.")
        }

        AIDebugLogStore.append(
            "REQUEST provider=\(settings.provider) model=\(settings.model)",
            details: AIDebugLogStore.hidesSensitiveInfo ? Self.redactedSchemas(saved: saved, fields: fields) : inputJSON
        )

        if settings.provider == "openai-decisions" || settings.provider == "umete" {
            do {
                let mappings = try await requestDecisions(settings, saved: saved, fields: fields)
                return mappings.filter { fieldIDs.contains($0["field"] ?? "") && savedIDs.contains($0["key"] ?? "") }
            } catch {
                AIDebugLogStore.append("ERROR provider=\(settings.provider)", details: error.localizedDescription)
                throw error
            }
        }

        let response: String
        do {
            response = settings.provider == "openai"
                ? try await requestOpenAI(settings, inputJSON: inputJSON)
                : try await requestAnthropic(settings, inputJSON: inputJSON)
            AIDebugLogStore.append("RESPONSE provider=\(settings.provider)", details: response)
        } catch {
            AIDebugLogStore.append("ERROR provider=\(settings.provider)", details: error.localizedDescription)
            throw error
        }

        guard let object = try JSONSerialization.jsonObject(with: Data(response.utf8)) as? [String: Any],
              let rawMappings = object["mappings"] as? [[String: Any]] else {
            throw MappingError.message("The provider returned an invalid field mapping.")
        }

        return rawMappings.compactMap { mapping in
            guard let field = mapping["field"] as? String,
                  let key = mapping["key"] as? String,
                  fieldIDs.contains(field), savedIDs.contains(key) else { return nil }
            return ["field": field, "key": key]
        }
    }

    private static func redactedSchemas(saved: [[String: Any]], fields: [[String: Any]]) -> String {
        let redact: ([[String: Any]]) -> [[String: Any]] = { list in
            list.map { schema in
                var copy = schema
                for key in ["label", "accessibleName", "accessibleDescription", "placeholder", "group", "section", "form", "optionLabel", "groupName", "tableHeaders", "options", "name", "id", "value"] {
                    copy[key] = nil
                }
                return copy
            }
        }
        let redacted: [String: Any] = ["savedFieldSchemas": redact(saved), "currentFormSchemas": redact(fields)]
        guard let data = try? JSONSerialization.data(withJSONObject: redacted, options: [.sortedKeys]),
              let json = String(data: data, encoding: .utf8) else { return "(redacted)" }
        return json
    }

    static let supportedProviders = SafariWebExtensionHandlerProviders.supported

    // MARK: - OpenAI Decisions API
    //
    // Each unmatched form field becomes one "choice" question whose options are
    // the saved answers (described by their labels, never their values) plus
    // "none". The API returns a probability per option, so a mapping is applied
    // only when the chosen answer is clearly ahead. Input tokens are the only
    // cost, so sending every compatible saved answer as an option is cheap.
    private static let decisionsEndpoint = "https://api.openai.com/v1/decisions"
    private static let decisionsDefaultModel = "gpt-6-luna"
    private static let umeteEndpoint = "https://api.umete.jp/v1/decisions"
    private static let decisionsQuestionsPerRequest = 10
    private static let decisionsMaximumChoices = 30
    private static let decisionsMaximumInputCharacters = 7_800
    private static let decisionsMaximumDescriptionCharacters = 280
    private static let decisionsMinimumProbability = 0.6
    private static let decisionsNone = "none"

    private func requestDecisions(_ settings: AISettings, saved: [[String: Any]], fields: [[String: Any]]) async throws -> [[String: String]] {
        let model = settings.model.trimmingCharacters(in: .whitespacesAndNewlines)
        var mappings: [[String: String]] = []
        var start = 0
        while start < fields.count {
            let chunk = Array(fields[start..<min(start + Self.decisionsQuestionsPerRequest, fields.count)])
            start += chunk.count
            let questions: [[String: Any]] = chunk.compactMap { field in
                guard let id = field["field"] as? String else { return nil }
                let choices = Self.decisionChoices(for: field, candidates: saved)
                guard !choices.isEmpty else { return nil }
                return [
                    "type": "choice",
                    "name": id,
                    "instructions": String(Self.decisionInstructions(for: field).prefix(600)),
                    "choices": [["value": Self.decisionsNone, "description": "No saved answer belongs in this field, or it is ambiguous which one does."]] + choices
                ]
            }
            guard !questions.isEmpty else { continue }
            let usesFreeService = settings.provider == "umete"
            var body: [String: Any] = [
                "input": Self.decisionInput(fields: chunk),
                "questions": questions
            ]
            if usesFreeService {
                body["device"] = UsageIdentity.deviceID
            } else {
                body["model"] = model.isEmpty ? Self.decisionsDefaultModel : model
            }
            let data = usesFreeService
                ? try await post(url: Self.umeteEndpoint, headers: ["X-Umete-Client": Self.clientVersion], body: body)
                : try await post(url: Self.decisionsEndpoint, headers: ["Authorization": "Bearer \(settings.apiKey)"], body: body)
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                throw MappingError.message("OpenAI returned an unreadable decision.")
            }
            if let error = (json["error"] as? [String: Any])?["message"] as? String { throw MappingError.message(error) }
            guard let answers = json["answers"] as? [[String: Any]] else {
                throw MappingError.message("OpenAI returned no decisions.")
            }
            var summary: [String] = []
            for answer in answers {
                guard let name = answer["name"] as? String else { continue }
                guard (answer["type"] as? String) == "choice", let choice = answer["choice"] as? String else {
                    summary.append("\(name): \(answer["type"] as? String ?? "unknown")")
                    continue
                }
                let probabilities = (answer["probabilities"] as? [[String: Any]] ?? []).reduce(into: [String: Double]()) { result, entry in
                    if let value = entry["value"] as? String, let probability = entry["probability"] as? Double { result[value] = probability }
                }
                let probability = probabilities[choice] ?? 0
                let accepted = choice != Self.decisionsNone && probability >= Self.decisionsMinimumProbability
                summary.append("\(name): \(choice) p=\(String(format: "%.2f", probability))\(accepted ? "" : " (skipped)")")
                if accepted { mappings.append(["field": name, "key": choice]) }
            }
            AIDebugLogStore.append("RESPONSE provider=openai-decisions", details: summary.joined(separator: "\n"))
        }
        return mappings
    }

    /// Human-readable description of a field or saved answer built from its
    /// sanitized schema. Values are never part of the schema, so none leak here.
    private static func describe(_ schema: [String: Any], includeOptions: Bool) -> String {
        var parts: [String] = []
        let name = [schema["userLabel"], schema["accessibleName"], schema["label"]].compactMap { $0 as? String }.first { !$0.isEmpty }
        if let name { parts.append("labeled \"\(name)\"") }
        if let type = schema["answerType"] as? String, !type.isEmpty { parts.append("type \(type)") }
        if let inputType = schema["inputType"] as? String, !inputType.isEmpty, inputType != "text" { parts.append("input \(inputType)") }
        if let kind = schema["kind"] as? String, !kind.isEmpty, kind != "text" { parts.append(kind) }
        if let autocomplete = schema["autocomplete"] as? String, !autocomplete.isEmpty { parts.append("autocomplete \(autocomplete)") }
        if let placeholder = schema["placeholder"] as? String, !placeholder.isEmpty { parts.append("placeholder \"\(placeholder)\"") }
        if let description = schema["accessibleDescription"] as? String, !description.isEmpty { parts.append("hint \"\(description)\"") }
        let context = [schema["group"], schema["section"], schema["form"]].compactMap { $0 as? String }.filter { !$0.isEmpty }
        if !context.isEmpty { parts.append("in \(context.map { "\"\($0)\"" }.joined(separator: " / "))") }
        if let headers = schema["tableHeaders"] as? [String], !headers.isEmpty { parts.append("columns \(headers.joined(separator: ", "))") }
        if includeOptions, let options = schema["options"] as? [String], !options.isEmpty {
            parts.append("options: \(options.prefix(12).joined(separator: " | "))")
        }
        if let name = schema["name"] as? String, !name.isEmpty { parts.append("name=\(name)") }
        return parts.isEmpty ? "unlabeled field" : parts.joined(separator: ", ")
    }

    private static func decisionInput(fields: [[String: Any]]) -> String {
        let lines = fields.compactMap { field -> String? in
            guard let id = field["field"] as? String else { return nil }
            return "- \(id): \(describe(field, includeOptions: true).prefix(decisionsMaximumDescriptionCharacters * 2))"
        }
        let text = "A web form has these unfilled fields. Each saved answer is described by what it was originally entered for, not its value.\n" + lines.joined(separator: "\n")
        return String(text.prefix(decisionsMaximumInputCharacters))
    }

    private static var clientVersion: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
        #if os(macOS)
        return "umete-macos/\(version)"
        #else
        return "umete-ios/\(version)"
        #endif
    }

    private static func decisionInstructions(for field: [String: Any]) -> String {
        let id = field["field"] as? String ?? "this field"
        return "Which saved answer should fill form field \(id) (\(describe(field, includeOptions: false)))? Choose a saved answer only when its meaning clearly matches this field. If nothing fits, or two could fit equally, choose none."
    }

    private static func tokens(_ schema: [String: Any]) -> Set<String> {
        let text = ["userLabel", "accessibleName", "label", "name", "placeholder", "autocomplete", "group", "section"]
            .compactMap { schema[$0] as? String }.joined(separator: " ")
            .replacingOccurrences(of: "([a-z])([A-Z])", with: "$1 $2", options: .regularExpression)
            .lowercased()
        return Set(text.split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map(String.init).filter { $0.count > 1 })
    }

    private static func decisionChoices(for field: [[String: Any]].Element, candidates: [[String: Any]]) -> [[String: Any]] {
        let fieldKind = field["kind"] as? String ?? "text"
        let fieldInputType = field["inputType"] as? String ?? ""
        let fieldTokens = tokens(field)
        let compatible = candidates.filter { candidate in
            let kind = candidate["kind"] as? String ?? "text"
            return (kind == "checkbox") == (fieldKind == "checkbox")
        }
        let ranked = compatible.map { candidate -> (score: Int, schema: [String: Any]) in
            var score = 0
            if (candidate["inputType"] as? String ?? "") == fieldInputType { score += 3 }
            if (candidate["kind"] as? String ?? "text") == fieldKind { score += 1 }
            score += tokens(candidate).intersection(fieldTokens).count * 2
            return (score, candidate)
        }
        let kept = ranked.count > decisionsMaximumChoices
            ? ranked.sorted { $0.score > $1.score }.prefix(decisionsMaximumChoices).map { $0.schema }
            : ranked.map { $0.schema }
        return kept.compactMap { candidate in
            guard let key = candidate["key"] as? String else { return nil }
            return ["value": key, "description": String("Saved answer \(describe(candidate, includeOptions: false))".prefix(decisionsMaximumDescriptionCharacters))]
        }
    }

    private func requestOpenAI(_ settings: AISettings, inputJSON: String) async throws -> String {
        let schema = mappingSchema()
        let body: [String: Any] = [
            "model": settings.model,
            "reasoning": ["effort": "high"],
            "instructions": systemPrompt,
            "input": inputJSON,
            "store": false,
            "text": ["format": ["type": "json_schema", "name": "ume_field_mapping", "strict": true, "schema": schema]]
        ]
        let data = try await post(url: "https://api.openai.com/v1/responses", headers: ["Authorization": "Bearer \(settings.apiKey)"], body: body)
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw MappingError.message("OpenAI returned an unreadable response.")
        }
        if let error = (json["error"] as? [String: Any])?["message"] as? String { throw MappingError.message(error) }
        if let output = json["output"] as? [[String: Any]] {
            for item in output {
                for content in item["content"] as? [[String: Any]] ?? [] {
                    if let text = content["text"] as? String { return text }
                }
            }
        }
        throw MappingError.message("OpenAI returned no mapping.")
    }

    private func requestAnthropic(_ settings: AISettings, inputJSON: String) async throws -> String {
        let body: [String: Any] = [
            "model": settings.model,
            "max_tokens": 2048,
            "system": systemPrompt,
            "messages": [["role": "user", "content": inputJSON]],
            "output_config": ["format": ["type": "json_schema", "schema": mappingSchema()]]
        ]
        let data = try await post(url: "https://api.anthropic.com/v1/messages", headers: [
            "x-api-key": settings.apiKey,
            "anthropic-version": "2023-06-01"
        ], body: body)
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw MappingError.message("Anthropic returned an unreadable response.")
        }
        if let error = (json["error"] as? [String: Any])?["message"] as? String { throw MappingError.message(error) }
        for content in json["content"] as? [[String: Any]] ?? [] {
            if let text = content["text"] as? String { return text }
        }
        throw MappingError.message("Anthropic returned no mapping.")
    }

    private func post(url: String, headers: [String: String], body: [String: Any]) async throws -> Data {
        guard let endpoint = URL(string: url) else { throw MappingError.message("Invalid provider endpoint.") }
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = 45
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        headers.forEach { request.setValue($0.value, forHTTPHeaderField: $0.key) }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, 200..<300 ~= http.statusCode else {
            let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
            let providerMessage = ((json?["error"] as? [String: Any])?["message"] as? String) ?? (json?["message"] as? String)
            throw MappingError.message(providerMessage ?? "The AI provider rejected the request.")
        }
        return data
    }

    private func complete(_ context: NSExtensionContext, _ message: [String: Any]) {
        let response = NSExtensionItem()
        if #available(iOS 15.0, macOS 11.0, *) {
            response.userInfo = [SFExtensionMessageKey: message]
        } else {
            response.userInfo = ["message": message]
        }
        context.completeRequest(returningItems: [response], completionHandler: nil)
    }

    private var systemPrompt: String {
        "Map semantically equivalent form fields. Return only confident one-to-one mappings. Never infer or invent values. Inputs contain schemas only, never user answers."
    }

    private func mappingSchema() -> [String: Any] {
        [
            "type": "object",
            "properties": [
                "mappings": [
                    "type": "array",
                    "items": [
                        "type": "object",
                        "properties": ["field": ["type": "string"], "key": ["type": "string"]],
                        "required": ["field", "key"],
                        "additionalProperties": false
                    ]
                ]
            ],
            "required": ["mappings"],
            "additionalProperties": false
        ]
    }
}
