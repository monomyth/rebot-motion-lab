import Foundation

/// Shared routing for the toolbar importer and the experiment's task loader.
public enum SimulatorDocument {
    case task(ExperimentTask)
    case trajectory(TrajectoryFile)

    public static func decode(_ data: Data) throws -> Self {
        guard data.count < 2_000_000 else { throw ExperimentError.invalid("Choose a JSON file smaller than 2 MB.") }
        let raw: Any
        do { raw = try JSONSerialization.jsonObject(with:data) }
        catch { throw ExperimentError.invalid("The selected file is not valid JSON.") }
        guard let object = raw as? [String:Any] else {
            throw ExperimentError.invalid("Load one task object. Collection task lists belong in the fly-brain CLI's --tasks option.")
        }
        let taskKeys = ["cube_size_mm", "cube_xy_mm", "initial_joints_deg", "input_mode"]
        let isTask = taskKeys.contains { object[$0] != nil }
        do {
            if isTask { return .task(try JSONDecoder().decode(ExperimentTask.self,from:data)) }
            if object["poses"] != nil || object["format"] != nil {
                return .trajectory(try JSONDecoder().decode(TrajectoryFile.self,from:data))
            }
            throw ExperimentError.invalid("Choose a cube task JSON file or an exported B601-DM trajectory.")
        } catch let error as DecodingError {
            let kind = isTask ? "Task" : "Trajectory"
            switch error {
            case .keyNotFound(let key, _):
                throw ExperimentError.invalid("\(kind) file is missing the field ‘\(key.stringValue)’. Use a complete saved task or trajectory.")
            case .typeMismatch(_, let context), .valueNotFound(_, let context), .dataCorrupted(let context):
                let field = context.codingPath.map(\.stringValue).joined(separator:".")
                throw ExperimentError.invalid("\(kind) field ‘\(field.isEmpty ? "root" : field)’ has an invalid value or type.")
            @unknown default:
                throw ExperimentError.invalid("The \(kind.lowercased()) file could not be decoded.")
            }
        }
    }
    public static func decodeTask(_ data: Data) throws -> ExperimentTask {
        guard case .task(let task) = try decode(data) else {
            throw ExperimentError.invalid("This is a motion trajectory. Use Import task or trajectory in the toolbar to load it.")
        }
        return task
    }
}
