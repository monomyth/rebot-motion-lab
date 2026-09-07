import Foundation

public enum Assets {
    // App bundles use Contents/Resources; SwiftPM uses its generated resource bundle.
    public static var root: URL {
        if let url = Bundle.main.resourceURL?.appendingPathComponent("RobotResources"),
           FileManager.default.fileExists(atPath: url.appendingPathComponent("model/model.json").path) { return url }
        let resourceURL = Bundle.module.resourceURL!
        if FileManager.default.fileExists(atPath: resourceURL.appendingPathComponent("model/model.json").path) { return resourceURL }
        return resourceURL.appendingPathComponent("Resources")
    }
    public static func url(_ path: String) -> URL { root.appendingPathComponent(path) }
    public static func decode<T: Decodable>(_ path: String, as type: T.Type) throws -> T {
        try JSONDecoder().decode(type, from: Data(contentsOf: url(path)))
    }
}

public struct RobotDefinition: Decodable, Sendable {
    public struct Visual: Decodable, Sendable {
        public let mesh: String
        public let material: String
        public let xyz: [Double]
        public let rpy: [Double]
    }
    public struct Link: Decodable, Sendable {
        public let name: String
        public let visuals: [Visual]
    }
    public struct Joint: Decodable, Sendable {
        public let name, type, parent, child: String
        public let axis, xyz, rpy: [Double]
        public let lower, upper: Double
    }
    public let source, commit: String
    public let materials: [String: [Double]]
    public let links: [Link]
    public let joints: [Joint]
    public var armJoints: [Joint] { joints.filter { $0.type == "revolute" } }
    public static func load() throws -> Self { try Assets.decode("model/model.json", as: Self.self) }
}

public struct ActuatorReference: Decodable, Sendable {
    public struct Source: Decodable, Identifiable, Sendable {
        public let id, title, url, detail: String
    }
    public struct Note: Decodable, Sendable { public let title, text: String; public let sources: [String]? }
    public struct Actuator: Decodable, Identifiable, Sendable {
        public var id: String { joint }
        public let joint, model, motor_id, feedback_id: String
        public let kp, kd, vel_kp, vel_ki, pos_kp, pos_ki, vlim, pmax, vmax, tmax: Double
        public let lower, upper, urdf_effort, urdf_velocity: Double?
    }
    public struct Setting: Decodable, Identifiable, Sendable {
        public var id: String { key }
        public let key, value, unit, description, source: String
    }
    public struct Command: Decodable, Identifiable, Sendable {
        public var id: String { key }
        public let key, range, unit, description: String
    }
    public struct Mode: Decodable, Identifiable, Sendable {
        public var id: Int { code }
        public let code: Int
        public let name, offset, description: String
    }
    public struct Operation: Decodable, Identifiable, Sendable {
        public var id: String { name }
        public let name, description, persistence, source: String
    }
    public struct Register: Decodable, Identifiable, Sendable {
        public var id: Int { rid }
        public let rid: Int
        public let name, access, range, type, category, unit, description: String
        public let extended: Bool
    }
    public let checked: String
    public let sources: [Source]
    public let notes: [Note]
    public let actuators: [Actuator]
    public let software: [Setting]
    public let commands: [Command]
    public let modes: [Mode]
    public let operations: [Operation]
    public let statuses: [[String]]
    public let registers: [Register]
    public let categories: [String]
    public static func load() throws -> Self { try Assets.decode("actuators.json", as: Self.self) }
}
