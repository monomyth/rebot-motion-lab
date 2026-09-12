import Foundation
import simd

/// Versioned sensor geometry shared by the spectator presets and recorded images.
/// Camera axes: right +X, up +Y, optical direction -Z. Robot base is Z-up; +X faces the work area.
public enum ObservationRig {
    public static let revision = "front336l-gripper305-rgb-v4"
    public static let observationNames = ["Front", "Gripper"]
    public static let viewNames = ["Orbit", "Front", "Top", "Gripper"]
    public static let frontEye = SIMD3<Double>(0.75, 0, 0.65)
    public static let frontTarget = SIMD3<Double>(0.15, 0, 0.05)
    // From the supplied cradle assembly: CAD (0,66,15) mm rear midpoint,
    // CAD Z -> tool X, CAD X -> tool Y, CAD Y -> tool Z, with fingertip origin.
    public static let gripperPitchDegrees = 15.0
    public static let gripperRearMidpoint = SIMD3<Double>(-0.0882093276977539, 0, 0.066)
    public static let gripperDirection = SIMD3<Double>(cos(gripperPitchDegrees * .pi/180),0,-sin(gripperPitchDegrees * .pi/180))
    // Ideal RGB pinhole at the nominal front plane, 23 mm ahead of the rear plate.
    public static let gripperEye = gripperRearMidpoint + gripperDirection * 0.023
    // Both devices publish RGB H94 x V68 (+/-3 deg) for their full 16:10 sensor mode.
    // The ideal pinhole at V68 and aspect 16:10 gives H94.3636, within that nominal specification.
    public static let imageWidth = 320
    public static func imageHeight(_ name: String) -> Int { observationNames.contains(name) ? 200 : 240 }
    public static func fieldOfView(_ name: String) -> Double { observationNames.contains(name) ? 68 : 38 }
    public static func horizontalFieldOfView(_ name: String) -> Double {
        2*atan(Double(imageWidth)/Double(imageHeight(name))*tan(fieldOfView(name) * .pi/360))*180 / .pi
    }
    public static func cameraModel(_ name: String) -> String {
        switch name {
        case "Front": return "Orbbec Gemini 336L (simulated RGB)"
        case "Gripper": return "Orbbec Gemini 305 (simulated RGB)"
        default: return "Virtual " + name
        }
    }
    public static func specificationURL(_ name: String) -> String {
        name == "Gripper" ? "https://www.orbbec.com/gemini-305/" : "https://store.orbbec.com/products/gemini-336l"
    }
    public static func focalLengthPixels(_ name: String) -> Double {
        Double(imageHeight(name))/2/tan(fieldOfView(name) * .pi/360)
    }
    /// Letterbox the sensor presets; arbitrary window aspect ratios must not change their FOV.
    public static func viewportSize(_ name: String, width: Double, height: Double) -> SIMD2<Double> {
        guard width.isFinite, height.isFinite, width > 0, height > 0 else { return .zero }
        guard observationNames.contains(name) else { return [width,height] }
        let aspect=Double(imageWidth)/Double(imageHeight(name))
        let fittedWidth=min(width,height*aspect)
        return [fittedWidth,fittedWidth/aspect]
    }
    public static func looking(from eye: SIMD3<Double>, at target: SIMD3<Double>, up: SIMD3<Double> = [0,0,1]) -> simd_double4x4 {
        let back = simd_normalize(eye - target)
        let right = simd_normalize(simd_cross(up, back))
        let cameraUp = simd_cross(back, right)
        return simd_double4x4(columns:(SIMD4(right,0), SIMD4(cameraUp,0), SIMD4(back,0), SIMD4(eye,1)))
    }
    /// Rigid transform in end_link coordinates; never aims at the object's location.
    public static var gripperHousingMount: simd_double4x4 {
        looking(from:gripperEye, at:gripperEye + gripperDirection)
    }
    public static var gripperMount: simd_double4x4 {
        // Gemini 305 has an 18 mm baseline. The controller uses one left RGB stream.
        var leftLens=matrix_identity_double4x4; leftLens[3].x = -0.009
        return gripperHousingMount * leftLens
    }
    public static func worldFromCamera(_ name: String, worldFromTool: simd_double4x4 = matrix_identity_double4x4) -> simd_double4x4 {
        switch name {
        case "Gripper": return worldFromTool * gripperMount
        case "Top": return looking(from:[0.2,-0.001,1.5],at:[0.2,0,0.2])
        default: return looking(from:frontEye,at:frontTarget)
        }
    }
}
