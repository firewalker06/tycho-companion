import XCTest
@testable import TychoCompanionKit

final class TychoCompanionKitTests: XCTestCase {
    func testActivityDecodesOptionalQueueAsUnknown() throws {
        let data = #"{"schema_version":1,"servers":[{"key":"a","name":"A","stale":false,"agents":[{"key":"x","name":"X","project_key":"p","status":"running","unread":false}]}]}"#.data(using: .utf8)!
        let value = try JSONDecoder().decode(ActivityCatalog.self, from: data)
        XCTAssertNil(value.servers[0].agents[0].promptQueueCount); XCTAssertEqual(value.servers[0].agents[0].effectiveState, .running)
    }
    func testStatePriorityAndMapping() { let agent = ActivityAgent(key: "x", name: "X", projectKey: "p", state: .running, awaitingInput: true, blocked: true); let entities = SceneMapper.map(NormalizedSnapshot(catalog: .init(servers: [.init(key: "s", name: "S", stale: true, agents: [agent])]))); XCTAssertEqual(entities.first?.cue, .closedGate); XCTAssertTrue(entities.first?.stale == true) }
    func testSafeOrigins() { XCTAssertNotNil(SafeOrigin.validate("http://127.0.0.1:7373")); XCTAssertNotNil(SafeOrigin.validate("https://tycho.example.ts.net")); XCTAssertNil(SafeOrigin.validate("https://example.com")); XCTAssertNil(SafeOrigin.validate("http://tycho.local")) }
    func testEvenLayoutIsStable() { XCTAssertEqual(StripLayout.positions(count: 3, width: 100), [42, 50, 58]); XCTAssertEqual(StripLayout.positions(count: 1, width: 100), [50]) }
}
