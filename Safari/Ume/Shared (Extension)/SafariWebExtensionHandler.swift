import SafariServices
import Security
import CryptoKit

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
        case "UME_OPEN_APP":
            guard let url = URL(string: "ume://onboarding") else {
                complete(context, ["ok": false, "error": "Ume could not open the companion app."])
                return
            }
            context.open(url) { [weak self] opened in
                self?.complete(context, opened
                    ? ["ok": true]
                    : ["ok": false, "error": "Open the Ume app to finish setup."])
            }
        case "UME_GET_ANSWERS":
            do {
                complete(context, ["ok": true, "answers": try AnswerStore.load()])
            } catch {
                complete(context, ["ok": false, "error": error.localizedDescription])
            }
        case "UME_SAVE_ANSWERS":
            do {
                let answers = payload["answers"] as? [[String: Any]] ?? []
                try AnswerStore.save(answers)
                complete(context, ["ok": true])
            } catch {
                complete(context, ["ok": false, "error": error.localizedDescription])
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

    private func mapFields(_ payload: [String: Any]) async throws -> [[String: String]] {
        guard let settings = SettingsStore.load(), ["openai", "anthropic"].contains(settings.provider), !settings.apiKey.isEmpty else {
            throw MappingError.message("Open the Ume app and add an OpenAI or Anthropic API key first.")
        }
        guard let saved = payload["saved"] as? [[String: Any]],
              let fields = payload["fields"] as? [[String: Any]],
              saved.count <= 200, fields.count <= 200 else {
            throw MappingError.message("The form mapping request was invalid or too large.")
        }

        let savedIDs = Set(saved.compactMap { $0["key"] as? String })
        let fieldIDs = Set(fields.compactMap { $0["field"] as? String })
        let input: [String: Any] = ["savedFieldSchemas": saved, "currentFormSchemas": fields]
        let inputData = try JSONSerialization.data(withJSONObject: input, options: [.sortedKeys])
        guard let inputJSON = String(data: inputData, encoding: .utf8) else {
            throw MappingError.message("Could not encode sanitized field schemas.")
        }

        let response = settings.provider == "openai"
            ? try await requestOpenAI(settings, inputJSON: inputJSON)
            : try await requestAnthropic(settings, inputJSON: inputJSON)

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

    private func requestOpenAI(_ settings: AISettings, inputJSON: String) async throws -> String {
        let schema = mappingSchema()
        let body: [String: Any] = [
            "model": settings.model,
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
            let providerMessage = ((json?["error"] as? [String: Any])?["message"] as? String)
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
