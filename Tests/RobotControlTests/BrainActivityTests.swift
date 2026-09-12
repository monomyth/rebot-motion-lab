import XCTest
import CryptoKit
@testable import RobotControl

final class BrainActivityTests: XCTestCase {
    private func object() -> [String: Any] {
        ["schema": "malecns-activity-v1", "episode_id": "new-episode", "frame_id": 20,
         "simulation_time": 4.0, "generated_at": 100.0, "layout_directory": "/tmp/layout",
         "graph_id": String(repeating: "a", count: 64), "count": 3,
         "metric": "mean_absolute_state", "values": Data([0, 128, 255]).base64EncodedString()]
    }
    private func decode(_ value: [String: Any]) throws -> BrainActivityFrame {
        try JSONDecoder().decode(BrainActivityFrame.self, from: JSONSerialization.data(withJSONObject: value))
    }
    func testLiveActivityRequiresCurrentEpisodeOwnerAndFreshTimestamp() throws {
        let frame = try decode(object()); try frame.validate()
        XCTAssertTrue(frame.isLive(episode: "new-episode", owner: "malecns", now: 100.2))
        XCTAssertFalse(frame.isLive(episode: "old-episode", owner: "malecns", now: 100.2))
        XCTAssertFalse(frame.isLive(episode: "new-episode", owner: "manual", now: 100.2))
        XCTAssertFalse(frame.isLive(episode: "new-episode", owner: "conventional", now: 100.2))
        XCTAssertFalse(frame.isLive(episode: "new-episode", owner: "malecns", now: 102))
        XCTAssertFalse(frame.isLive(episode: "new-episode", owner: "malecns", now: 90))
    }
    func testTruncatedAndOversizedFramesAreRejected() throws {
        var value = object(); value["count"] = 4
        XCTAssertThrowsError(try decode(value).validate())
        value = object(); value["count"] = 200_001
        XCTAssertThrowsError(try decode(value).validate())
        value = object(); value["metric"] = "spikes"
        XCTAssertThrowsError(try decode(value).validate())
    }
    func testLayoutChecksHashAndFiniteCoordinates() throws {
        func layout(_ data: Data) throws -> BrainSomaLayout {
            let value: [String: Any] = ["schema": "malecns-soma-layout-v1", "graph_id": String(repeating: "a", count: 64),
                "count": 1, "total_neurons": 2, "missing_positions": 1,
                "files": ["positions.f32": SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()]]
            return try JSONDecoder().decode(BrainSomaLayout.self, from: JSONSerialization.data(withJSONObject: value))
        }
        let valid = [Float(0), Float(-1), Float(1)].withUnsafeBytes { Data($0) }
        try layout(valid).validate(positions: valid)
        XCTAssertThrowsError(try layout(valid).validate(positions: Data(repeating: 0, count: 12)))
        let nonfinite = [Float.nan, Float(0), Float(0)].withUnsafeBytes { Data($0) }
        XCTAssertThrowsError(try layout(nonfinite).validate(positions: nonfinite))
    }
    func testContrastExposesSmallValuesWithoutInventingZeroActivity() {
        XCTAssertEqual(BrainActivityDisplay.contrast(0), 0)
        XCTAssertEqual(BrainActivityDisplay.contrast(1), 1, accuracy: 0.00001)
        XCTAssertGreaterThan(BrainActivityDisplay.contrast(0.004), 0.2)
        XCTAssertLessThan(BrainActivityDisplay.contrast(0.01), BrainActivityDisplay.contrast(0.1))
    }
    func testHighlightsUseActualDifferencesAndClearOnNewEpisode() throws {
        let previous = try decode(object())
        var next = object(); next["frame_id"] = 21; next["generated_at"] = 100.2
        next["values"] = Data([2, 128, 245]).base64EncodedString()
        let current = try decode(next)
        let display = BrainActivityDisplay(frame: current, previous: previous, highlightLimit: 1)
        XCTAssertEqual(display.changedCount, 2)
        XCTAssertEqual(display.highlightIndices, [2])
        XCTAssertEqual(display.changes[1], 0)
        XCTAssertEqual(display.changes[2], Float(10) / 255, accuracy: 0.00001)
        XCTAssertEqual(display.peak, Float(245) / 255, accuracy: 0.00001)
        next["episode_id"] = "another-episode"
        let reset = BrainActivityDisplay(frame: try decode(next), previous: previous)
        XCTAssertEqual(reset.changedCount, 0)
        XCTAssertTrue(reset.highlightIndices.isEmpty)
        XCTAssertTrue(BrainActivityDisplay(frame: current, previous: current).highlightIndices.isEmpty)
    }
    func testIdenticalActivityProducesNoDecorativeHighlights() throws {
        let previous = try decode(object())
        var next = object(); next["frame_id"] = 21; next["generated_at"] = 100.2
        let still = BrainActivityDisplay(frame: try decode(next), previous: previous)
        XCTAssertEqual(still.changedCount, 0)
        XCTAssertTrue(still.highlightIndices.isEmpty)
        next["generated_at"] = 110.0; next["values"] = Data([250, 128, 0]).base64EncodedString()
        XCTAssertTrue(BrainActivityDisplay(frame: try decode(next), previous: previous).highlightIndices.isEmpty)
    }

    func testDopamineTelemetryIsOptionalAndValidated() throws {
        XCTAssertNil(try decode(object()).dopamine)
        var value=object()
        value["dopamine"]=["signal":0.4,"reward":1.0,"cells":44,"weight_change_l1":0.03]
        let frame=try decode(value);try frame.validate()
        XCTAssertEqual(frame.dopamine?.cells,44)
        value["dopamine"]=["signal":1.1,"reward":1.0,"cells":44,"weight_change_l1":0.03]
        XCTAssertThrowsError(try decode(value).validate())
        value["dopamine"]=["signal":0.4,"reward":1.0,"cells":44,"weight_change_l1":-0.03]
        XCTAssertThrowsError(try decode(value).validate())
    }

    func testSevenMotorDriveTelemetryRejectsMalformedChannels() throws {
        var value=object()
        value["motor"]=["scores":[0.0,0.1,-0.2,0.0,0.4,-0.5,0.6],"choices":[2,1,0,2,1,0,1],"motor_circuit_id":String(repeating:"c",count:64)]
        let frame=try decode(value);try frame.validate()
        XCTAssertEqual(frame.motor?.scores.count,7)
        value["motor"]=["scores":[0.0],"choices":[2],"motor_circuit_id":String(repeating:"c",count:64)]
        XCTAssertThrowsError(try decode(value).validate())
    }

}
