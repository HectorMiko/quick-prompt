import Foundation

/// One user prompt. `prompt` is the system prompt sent to Claude.
/// Empty model settings take the model defaults (see `TextAction(prompt:)`).
public struct PromptItem: Codable, Identifiable, Hashable, Sendable {
    public let id: String
    public var name: String
    public var prompt: String
    public var backend: Backend?
    public var model: String?
    public var effort: Effort?
    public var timeoutSeconds: Double?
    public var maxTokens: Int?

    public init(
        id: String = UUID().uuidString,
        name: String,
        prompt: String,
        backend: Backend? = nil,
        model: String? = nil,
        effort: Effort? = nil,
        timeoutSeconds: Double? = nil,
        maxTokens: Int? = nil
    ) {
        self.id = id
        self.name = name
        self.prompt = prompt
        self.backend = backend
        self.model = model
        self.effort = effort
        self.timeoutSeconds = timeoutSeconds
        self.maxTokens = maxTokens
    }

    /// Name and prompt are both required.
    public var isValid: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

/// Content of `prompts.json`: the ordered prompt list and the quick action (double Cmd+C).
public struct PromptLibrary: Codable, Equatable, Sendable {
    public var quickActionID: String?
    public var prompts: [PromptItem]

    enum CodingKeys: String, CodingKey {
        case quickActionID = "quickActionId"
        case prompts
    }

    public init(quickActionID: String? = nil, prompts: [PromptItem] = []) {
        self.quickActionID = quickActionID
        self.prompts = prompts
    }

    public var quickAction: PromptItem? {
        prompts.first { $0.id == quickActionID }
    }

    /// Prompts shown in the palette: valid ones, in list order.
    public var runnablePrompts: [PromptItem] {
        prompts.filter(\.isValid)
    }

    /// Names (trimmed, case-insensitive) used by more than one prompt.
    public var duplicateNames: Set<String> {
        var counts: [String: Int] = [:]
        for prompt in prompts {
            let key = Self.nameKey(prompt.name)
            guard !key.isEmpty else { continue }
            counts[key, default: 0] += 1
        }
        return Set(counts.filter { $0.value > 1 }.keys)
    }

    public func hasDuplicateName(_ prompt: PromptItem) -> Bool {
        duplicateNames.contains(Self.nameKey(prompt.name))
    }

    static func nameKey(_ name: String) -> String {
        name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    // MARK: - Mutations

    @discardableResult
    public mutating func add(_ prompt: PromptItem = PromptItem(name: "New prompt", prompt: "")) -> PromptItem {
        prompts.append(prompt)
        return prompt
    }

    public mutating func update(_ prompt: PromptItem) {
        guard let index = prompts.firstIndex(where: { $0.id == prompt.id }) else { return }
        prompts[index] = prompt
    }

    /// Deleting the quick action leaves no quick action set.
    public mutating func delete(id: String) {
        prompts.removeAll { $0.id == id }
        if quickActionID == id { quickActionID = nil }
    }

    public mutating func move(fromOffsets source: IndexSet, toOffset destination: Int) {
        let moving = source.map { prompts[$0] }
        var remaining = prompts.enumerated().filter { !source.contains($0.offset) }.map(\.element)
        let insertAt = destination - source.filter { $0 < destination }.count
        remaining.insert(contentsOf: moving, at: max(0, min(insertAt, remaining.count)))
        prompts = remaining
    }

    /// `nil` clears the quick action. Unknown ids are ignored.
    public mutating func setQuickAction(id: String?) {
        guard id == nil || prompts.contains(where: { $0.id == id }) else { return }
        quickActionID = id
    }
}

/// Reads and writes `prompts.json`.
public enum PromptFile {
    public enum LoadError: Error, Equatable {
        case unreadable(String)
        case invalid(String)
    }

    /// Returns `nil` when the file does not exist yet.
    public static func load(from url: URL) throws(LoadError) -> PromptLibrary? {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            throw .unreadable(error.localizedDescription)
        }
        do {
            return try JSONDecoder().decode(PromptLibrary.self, from: data)
        } catch {
            throw .invalid(describe(error))
        }
    }

    public static func save(_ library: PromptLibrary, to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        try encoder.encode(library).write(to: url, options: .atomic)
    }

    /// Short decoding error description, without file content.
    static func describe(_ error: Error) -> String {
        guard let error = error as? DecodingError else { return "Invalid JSON" }
        switch error {
        case let .keyNotFound(key, context):
            return "Missing key \"\(key.stringValue)\" at \(path(context))"
        case let .typeMismatch(_, context), let .valueNotFound(_, context):
            return "Wrong value at \(path(context))"
        case let .dataCorrupted(context):
            return context.codingPath.isEmpty ? "Invalid JSON" : "Invalid value at \(path(context))"
        @unknown default:
            return "Invalid JSON"
        }
    }

    private static func path(_ context: DecodingError.Context) -> String {
        let path = context.codingPath.map { $0.intValue.map { "[\($0)]" } ?? $0.stringValue }.joined(separator: ".")
        return path.isEmpty ? "root" : path
    }
}
