import Foundation

public enum VisualCue: String, Sendable, Equatable { case rest, workbench, questionLantern, closedGate, warmLamp, rainCloud, crackedSign, stoppedTool }
public struct SceneEntity: Sendable, Equatable, Identifiable { public let id: String; public let serverName: String; public let projectKey: String; public let agentName: String; public let cue: VisualCue; public let unread: Bool; public let stale: Bool; public let queueCount: Int? }
public enum SceneMapper {
    public static func map(_ snapshot: NormalizedSnapshot) -> [SceneEntity] {
        snapshot.servers.flatMap { server in server.agents.map { agent in
            let cue: VisualCue = switch agent.effectiveState { case .idle: .rest; case .running: .workbench; case .awaitingInput: .questionLantern; case .blocked: .closedGate; case .succeeded: .warmLamp; case .failed: .rainCloud; case .partial: .crackedSign; case .stopped: .stoppedTool }
            return SceneEntity(id: "\(server.key)/\(agent.key)", serverName: server.name, projectKey: agent.projectKey, agentName: agent.name, cue: cue, unread: agent.unread, stale: server.stale || server.status == "offline", queueCount: agent.promptQueueCount)
        }}.sorted { $0.id < $1.id }
    }
}

public enum StripLayout {
    public static func positions(count: Int, width: Double, inset: Double = 42) -> [Double] {
        guard count > 0 else { return [] }; guard count > 1 else { return [width / 2] }
        let available = max(0, width - 2 * inset); return (0..<count).map { inset + available * Double($0) / Double(count - 1) }
    }
}
