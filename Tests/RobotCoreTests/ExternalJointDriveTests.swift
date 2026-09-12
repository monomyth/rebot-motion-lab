import Testing
@testable import RobotCore

struct ExternalJointDriveTests {
    @Test func smallCorrectionsDoNotRunAtFullJointSpeed() {
        let dt=1.0/60
        let next=ExternalJointDrive.advance(current:[0,0,0,0,0,0],target:[1,-0.5,0.25,0,0,0],seconds:dt)
        #expect(next[0]/dt < 1.5)
        #expect(abs(next[1]/next[0]+0.5) < 1e-10)
        #expect(abs(next[2]/next[0]-0.25) < 1e-10)
    }
    @Test func largeMovesRespectSpeedAndApproachWithoutOvershoot() {
        let target=[90.0,-90,45,0,0,0], dt=1.0/60
        var pose=[Double](repeating:0,count:6)
        for _ in 0..<900 {
            let next=ExternalJointDrive.advance(current:pose,target:target,seconds:dt)
            #expect(zip(pose,next).allSatisfy { abs($1-$0)<=30*dt+1e-10 })
            #expect(next[0]<=target[0] && next[1]>=target[1])
            pose=next
        }
        #expect(zip(pose,target).allSatisfy { abs($1-$0)<0.001 })
    }
}
