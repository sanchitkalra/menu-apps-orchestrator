import XCTest
@testable import OrchestratorCore

final class IPCBridgeTests: XCTestCase {
    func testParseInterval() async {
        XCTAssertEqual(Scheduler.parseInterval("5m"), 300)
        XCTAssertEqual(Scheduler.parseInterval("60s"), 60)
        XCTAssertEqual(Scheduler.parseInterval("1h"), 3600)
    }
    func testManifestDecode() throws {
        let json = """
        {"id":"todo","name":"Todos","version":"0.1.0","entrypoint":"bun run index.ts","lifecycle":"persistent","tile":{"size":"2x1"},"permissions":["store"]}
        """.data(using: .utf8)!
        let m = try JSONDecoder().decode(Manifest.self, from: json)
        XCTAssertEqual(m.id, "todo")
        XCTAssertEqual(m.lifecycle, .persistent)
    }
    func testDSLRoundTrip() throws {
        let node = Node.vstack(gap: "md", children: [.text(text: "hi", variant: "title", color: nil)])
        let data = try JSONEncoder().encode(node)
        let decoded = try JSONDecoder().decode(Node.self, from: data)
        XCTAssertEqual(node, decoded)
    }
}
