import Testing
@testable import RobotCore

struct GripperContactStopTests {
    @Test func widthEstimateWithoutContactCannotFreezeTheJaws() {
        var stop=GripperContactStop()
        let actual=20.81571658569264
        let next=stop.aperture(current:actual,requested:0,estimatedWidth:actual+0.02,bilateralContact:false)
        #expect(next < actual)
        #expect(abs(next-(actual-0.05)) < 1e-10)
    }
    @Test func preloadDoesNotAccumulateAndOpeningReleases() {
        var stop=GripperContactStop(); var aperture=20.0
        for _ in 0..<100 { aperture=stop.aperture(current:aperture,requested:0,estimatedWidth:20,bilateralContact:true) }
        #expect(abs(aperture-19.85) < 1e-10)
        #expect(stop.aperture(current:aperture,requested:90,estimatedWidth:20,bilateralContact:true)==90)
        #expect(stop.aperture(current:0.02,requested:0,estimatedWidth:20,bilateralContact:false)==0)
    }
    @Test func aLevelingCubeMaintainsTheMeasuredPreload() {
        var stop=GripperContactStop(); var aperture=20.4
        for _ in 0..<20 { aperture=stop.aperture(current:aperture,requested:0,estimatedWidth:20.4,bilateralContact:true) }
        for _ in 0..<20 { aperture=stop.aperture(current:aperture,requested:0,estimatedWidth:20,bilateralContact:false) }
        #expect(abs(aperture-19.85) < 1e-10)
        stop.reset()
        #expect(stop.aperture(current:25,requested:24,estimatedWidth:20,bilateralContact:false)==24)
    }
}
