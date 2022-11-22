import MetalKit
import simd

let FACE_MASK_NONE       0
let FACE_MASK_NEGATIVE_X (1 << 0)
let FACE_MASK_POSITIVE_X (1 << 1)
let FACE_MASK_NEGATIVE_Y (1 << 2)
let FACE_MASK_POSITIVE_Y (1 << 3)
let FACE_MASK_NEGATIVE_Z (1 << 4)
let FACE_MASK_POSITIVE_Z (1 << 5)
let FACE_MASK_ALL        ((1 << 6) - 1)

struct BoundingBox {
    MTLPackedFloat3 min
    MTLPackedFloat3 max
}

protocol Geometry: NSObject {
    var device: MTLDevice { get }
    var intersectionFunctionName: NSString { get }

    init(device: MTLDevice) // initWithDevice

    func clear() -> Void
    func uploadToBuffers() -> Void
    func geometryDescriptor() -> MTLAccelerationStructureGeometryDescriptor
    func resources() -> [MTLResource]
}

protocol TriangleGeometry: Geometry {
    func addCubeWithFaces(faceMask: UInt, color: vector_float3, transform: matrix_float4x4, inwardNormals: Bool) -> Void
}

protocol SphereGeometry: Geometry {
    func addSphereWithOrigin(origin: vector_float3, radius: Float, color: vector_float3) -> Void
}

protocol GeometryInstance: NSObject {
    var geometry: Geometry { get }
    var transform: matrix_float4x4 { get }
    var mask: UInt { get }
}

protocol Scene: NSObject {
    var device: MTLDevice { get }
    var geometries: [Geometry] { get }
    var instances: [GeometryInstance] { get }
    var lightBuffer: MTLBuffer { get }
    var lightCount: NSUInteger { get }

    var cameraPosition: vector_float3 { get set }
    var cameraTarget: vector_float3 { get set }
    var cameraUp: vector_float3 { get set }

    init(device: MTLDevice) // initWithDevice

    class func newInstancedCornellBoxSceneWithDevice(device: MTLDevice, useIntersectionFunctions: Bool) -> Scene

    func addGeometry(geometries: Geometry) -> Void
    func addInstance(instance: GeometryInstance) -> Void
    func addLight(light: AreaLight) -> Void
    func clear() -> Void
    func uploadToBuffers() -> Void
}
