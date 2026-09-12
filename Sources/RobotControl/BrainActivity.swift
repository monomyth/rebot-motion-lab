import Foundation
import CryptoKit

/// Display-only data. No values in this protocol authorize or command robot motion.
public struct BrainActivityFrame: Decodable {
    public let schema: String
    public let episode_id: String
    public let frame_id: Int
    public let simulation_time: Double
    public let generated_at: Double
    public let layout_directory: String
    public let graph_id: String
    public let count: Int
    public let metric: String
    public let values: Data
    public let dopamine: BrainDopamineActivity?
    public let motor: BrainMotorActivity?

    public func validate() throws {
        guard schema == "malecns-activity-v1", metric == "mean_absolute_state",
              (1...200_000).contains(count), values.count == count,
              frame_id >= 0, simulation_time.isFinite, generated_at.isFinite,
              Self.validGraphID(graph_id), layout_directory.hasPrefix("/") else {
            throw ControlError("Invalid brain activity frame")
        }
        if let motor {
            guard motor.scores.count == 7, motor.choices.count == 7,
                  motor.scores.allSatisfy({ $0.isFinite && abs($0) <= 1_000_000 }),
                  motor.choices.allSatisfy({ (0...2).contains($0) }),
                  Self.validGraphID(motor.motor_circuit_id) else { throw ControlError("Invalid motor activity") }
        }
        if let dopamine {
            guard dopamine.signal.isFinite, dopamine.reward.isFinite, dopamine.weight_change_l1.isFinite,
                  abs(dopamine.signal) <= 1, (0...1).contains(dopamine.reward),
                  (0...2_000).contains(dopamine.cells), dopamine.weight_change_l1 >= 0 else {
                throw ControlError("Invalid dopamine activity")
            }
        }
    }
    public func isLive(episode: String, owner: String, now: Double) -> Bool {
        let age = now - generated_at
        return episode_id == episode && owner == "malecns" && age >= -0.5 && age <= 1.5
    }
    public static func validGraphID(_ id: String) -> Bool {
        id.count == 64 && id.allSatisfy { "0123456789abcdef".contains($0) }
    }
}

public struct BrainSomaLayout: Decodable {
    public let schema: String
    public let graph_id: String
    public let count: Int
    public let total_neurons: Int
    public let missing_positions: Int
    public let files: [String: String]

    public func validate(positions: Data) throws {
        guard schema == "malecns-soma-layout-v1", BrainActivityFrame.validGraphID(graph_id),
              (1...200_000).contains(count), total_neurons >= count, total_neurons <= 200_000,
              missing_positions == total_neurons - count, positions.count == count * 12 else {
            throw ControlError("Invalid brain soma layout")
        }
        let digest = SHA256.hash(data: positions).map { String(format: "%02x", $0) }.joined()
        guard files["positions.f32"] == digest else { throw ControlError("Brain geometry checksum mismatch") }
        let valid = positions.withUnsafeBytes { bytes in
            stride(from: 0, to: bytes.count, by: 4).allSatisfy { offset in
                let word = UInt32(littleEndian: bytes.loadUnaligned(fromByteOffset: offset, as: UInt32.self))
                let value = Float(bitPattern: word)
                return value.isFinite && abs(value) <= 1.001
            }
        }
        guard valid else { throw ControlError("Invalid brain coordinates") }
    }
}

/// Fixed display gain; reported values and the controller state stay unmodified.
public struct BrainActivityDisplay {
    public let magnitudes: [Float]
    public let changes: [Float]
    public let highlightIndices: [UInt32]
    public let changedCount: Int
    public let mean: Float
    public let peak: Float

    public static func contrast(_ value: Float) -> Float {
        log1p(999 * max(0, min(1, value))) / log(1000)
    }

    public init(frame: BrainActivityFrame, previous: BrainActivityFrame?, highlightLimit: Int = 4_000) {
        let bytes = Array(frame.values)
        let comparable = previous.map {
            $0.episode_id == frame.episode_id && $0.graph_id == frame.graph_id &&
            $0.values.count == bytes.count && $0.frame_id < frame.frame_id &&
            $0.generated_at < frame.generated_at && frame.generated_at - $0.generated_at <= 1.5
        } ?? false
        let before = comparable ? Array(previous!.values) : nil
        var histogram = [Int](repeating: 0, count: 256)
        var deltas = [UInt8](repeating: 0, count: bytes.count)
        var total = 0
        var maximum: UInt8 = 0
        for index in bytes.indices {
            total += Int(bytes[index]); maximum = max(maximum, bytes[index])
            if let before { deltas[index] = UInt8(abs(Int(bytes[index]) - Int(before[index]))) }
            histogram[Int(deltas[index])] += 1
        }
        let changed = bytes.count - histogram[0]
        let limit = max(0, highlightLimit)
        var cutoff = 255, selected = 0
        while cutoff > 1 {
            if selected + histogram[cutoff] >= limit { break }
            selected += histogram[cutoff]; cutoff -= 1
        }
        // All values above the cutoff are stronger; stable body order breaks ties.
        var highlights = bytes.indices.filter { Int(deltas[$0]) > cutoff }.prefix(limit).map(UInt32.init)
        if highlights.count < limit {
            for index in bytes.indices where Int(deltas[index]) == cutoff {
                if highlights.count == limit { break }
                highlights.append(UInt32(index))
            }
        }
        magnitudes = bytes.map { Float($0) / 255 }
        changes = deltas.map { Float($0) / 255 }
        highlightIndices = highlights
        changedCount = changed
        mean = bytes.isEmpty ? 0 : Float(total) / Float(bytes.count) / 255
        peak = Float(maximum) / 255
    }
}

public struct BrainDopamineActivity: Decodable {
    public let signal: Double
    public let reward: Double
    public let cells: Int
    public let weight_change_l1: Double
}

public struct BrainMotorActivity: Decodable {
    public let scores: [Double]
    public let choices: [Int]
    public let motor_circuit_id: String
}
