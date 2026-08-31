import Foundation

public enum AgentState: String, Codable, Sendable, CaseIterable {
    case idle, running, awaitingInput = "awaiting-input", blocked, succeeded, failed, partial, stopped

    public init(status: String?) {
        switch status?.lowercased() {
        case "running": self = .running
        case "awaiting-input", "awaiting_input": self = .awaitingInput
        case "blocked": self = .blocked
        case "succeeded", "success", "completed": self = .succeeded
        case "failed", "failure": self = .failed
        case "partial": self = .partial
        case "stopped", "cancelled", "canceled": self = .stopped
        default: self = .idle
        }
    }
}

public struct ActivityAgent: Decodable, Sendable, Equatable, Identifiable {
    public let key: String
    public let name: String
    public let projectKey: String
    public let state: AgentState
    public let unread: Bool
    public let awaitingInput: Bool
    public let blocked: Bool
    public let scheduled: Bool
    public let promptQueueCount: Int?

    public var id: String { key }
    public var effectiveState: AgentState { blocked ? .blocked : (awaitingInput ? .awaitingInput : state) }

    enum CodingKeys: String, CodingKey { case key, name, projectKey = "project_key", status, unread, awaitingInput = "awaiting_input", blocked, scheduled, promptQueueCount = "prompt_queue_count" }
    public init(key: String, name: String, projectKey: String, state: AgentState, unread: Bool = false, awaitingInput: Bool = false, blocked: Bool = false, scheduled: Bool = false, promptQueueCount: Int? = nil) { self.key = key; self.name = name; self.projectKey = projectKey; self.state = state; self.unread = unread; self.awaitingInput = awaitingInput; self.blocked = blocked; self.scheduled = scheduled; self.promptQueueCount = promptQueueCount }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        key = try c.decode(String.self, forKey: .key); name = try c.decode(String.self, forKey: .name); projectKey = try c.decode(String.self, forKey: .projectKey)
        state = AgentState(status: try c.decodeIfPresent(String.self, forKey: .status))
        unread = try c.decodeIfPresent(Bool.self, forKey: .unread) ?? false; awaitingInput = try c.decodeIfPresent(Bool.self, forKey: .awaitingInput) ?? false; blocked = try c.decodeIfPresent(Bool.self, forKey: .blocked) ?? false; scheduled = try c.decodeIfPresent(Bool.self, forKey: .scheduled) ?? false; promptQueueCount = try c.decodeIfPresent(Int.self, forKey: .promptQueueCount)
    }
}

public struct ActivityServer: Decodable, Sendable, Equatable, Identifiable {
    public let key: String; public let name: String; public let stale: Bool; public let status: String?; public let agents: [ActivityAgent]
    public var id: String { key }
    public init(key: String, name: String, stale: Bool = false, status: String? = nil, agents: [ActivityAgent]) { self.key = key; self.name = name; self.stale = stale; self.status = status; self.agents = agents }
}

public struct ActivityCatalog: Decodable, Sendable, Equatable {
    public let schemaVersion: Int; public let revision: String?; public let generatedAt: Date?; public let servers: [ActivityServer]
    enum CodingKeys: String, CodingKey { case schemaVersion = "schema_version", revision, generatedAt = "generated_at", servers }
    public init(schemaVersion: Int = 1, revision: String? = nil, generatedAt: Date? = nil, servers: [ActivityServer]) { self.schemaVersion = schemaVersion; self.revision = revision; self.generatedAt = generatedAt; self.servers = servers }
}

public struct NormalizedSnapshot: Sendable, Equatable { public let servers: [ActivityServer]; public init(catalog: ActivityCatalog) { servers = catalog.servers.sorted { $0.key < $1.key } } }
