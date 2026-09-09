import Foundation
import AppKit
import simd

// Validate the actual encoded images and project the known initial cube into Front.
// Usage: swift scripts/check-camera-calibration.swift /path/to/initial-observation.json
enum CameraCheckError: Error { case failed(String) }
guard CommandLine.arguments.count == 2 else { throw CameraCheckError.failed("Pass an initial state-assisted observation JSON file.") }
let url=URL(fileURLWithPath:CommandLine.arguments[1])
let observation=try JSONSerialization.jsonObject(with:Data(contentsOf:url)) as! [String:Any]
let images=observation["images"] as! [[String:Any]]
guard images.count == 2 else { throw CameraCheckError.failed("Expected two observation cameras.") }
var sizes=[[String:Any]]()
for image in images {
    let data=Data(base64Encoded:image["jpeg_base64"] as! String)!
    guard let bitmap=NSBitmapImageRep(data:data), bitmap.pixelsWide == image["width"] as! Int, bitmap.pixelsHigh == image["height"] as! Int else { throw CameraCheckError.failed("Encoded size disagrees with calibration.") }
    sizes.append(["camera":image["name"]!,"width":bitmap.pixelsWide,"height":bitmap.pixelsHigh])
}
let camera=images.first { $0["name"] as? String == "Front" }!
let rows=camera["world_from_camera"] as! [[Double]]
let m=simd_double4x4(columns:(SIMD4(rows[0][0],rows[1][0],rows[2][0],rows[3][0]),SIMD4(rows[0][1],rows[1][1],rows[2][1],rows[3][1]),SIMD4(rows[0][2],rows[1][2],rows[2][2],rows[3][2]),SIMD4(rows[0][3],rows[1][3],rows[2][3],rows[3][3])))
let cube=observation["cube_pose"] as! [String:Any], position=cube["position_mm"] as! [Double]
let p=m.inverse * SIMD4(position[0]/1000,position[1]/1000,position[2]/1000,1)
let k=camera["intrinsics"] as! [[Double]]
let u=k[0][0]*p.x / -p.z+k[0][2], v=k[1][2]-k[1][1]*p.y / -p.z
let bitmap=NSBitmapImageRep(data:Data(base64Encoded:camera["jpeg_base64"] as! String)!)!
var minimum=Double.infinity, orangePixels=0
for y in 0..<bitmap.pixelsHigh {
    for x in 0..<bitmap.pixelsWide {
        guard let c=bitmap.colorAt(x:x,y:y)?.usingColorSpace(.deviceRGB) else { continue }
        if c.redComponent > 0.7, c.greenComponent > 0.25, c.greenComponent < 0.8, c.blueComponent < 0.5 {
            minimum=min(minimum,hypot(Double(x)-u,Double(y)-v)); orangePixels += 1
        }
    }
}
guard minimum < 3, orangePixels >= 10 else { throw CameraCheckError.failed("Projected cube does not align with the visible cube: \(minimum) pixels.") }
let report:[String:Any] = ["success":true,"encoded_sizes":sizes,"cube_projected_pixel":[u,v],"nearest_cube_pixel_error":minimum,"orange_pixels":orangePixels]
print(String(decoding:try JSONSerialization.data(withJSONObject:report,options:[.prettyPrinted,.sortedKeys]),as:UTF8.self))
