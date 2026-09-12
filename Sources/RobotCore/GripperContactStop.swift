import Foundation

/// A small pad preload maintains a measured grasp as the object's orientation changes.
public struct GripperContactStop {
    private var contactWidth: Double?
    private var contactEstimate: Double?
    public init() {}
    public mutating func reset() { contactWidth=nil; contactEstimate=nil }
    public mutating func aperture(current: Double, requested: Double, estimatedWidth: Double,
                                  bilateralContact: Bool) -> Double {
        if requested > current { reset(); return requested }
        guard requested < current else { return requested }
        if bilateralContact, contactWidth == nil {
            contactWidth=current; contactEstimate=estimatedWidth
        }
        if let contactWidth, let contactEstimate {
            // Latch once: the 0.15 mm total preload must not accumulate each frame.
            // Track changes in projected width around the *measured* contact width.
            let target=contactWidth-0.15+(estimatedWidth-contactEstimate)
            return max(requested,min(current,max(current-0.05,target)))
        }
        // Finite pads may need to close below the complete cube's projected width.
        if current <= estimatedWidth+1 { return max(requested,current-0.05) }
        return requested
    }
}
