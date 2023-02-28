import MetalKit
import simd

let FACE_MASK_NONE: UInt = 0
let FACE_MASK_NEGATIVE_X: UInt = 1 << 0
let FACE_MASK_POSITIVE_X: UInt = 1 << 1
let FACE_MASK_NEGATIVE_Y: UInt = 1 << 2
let FACE_MASK_POSITIVE_Y: UInt = 1 << 3
let FACE_MASK_NEGATIVE_Z: UInt = 1 << 4
let FACE_MASK_POSITIVE_Z: UInt = 1 << 5
let FACE_MASK_ALL: UInt = (1 << 6) - 1

struct BoundingBox {
    var min = MTLPackedFloat3()
    var max = MTLPackedFloat3()
}

func getTriangleNormal(_ v0: vector_float3, _ v1: vector_float3, _ v2: vector_float3) -> vector_float3 {
    let e1 = simd_normalize(v1 - v0)
    let e2 = simd_normalize(v2 - v0)

    return simd_cross(e1, e2)
}

protocol Geometry {
    var device:                   MTLDevice { get }
    var intersectionFunctionName: String    { get }

    init(device: MTLDevice)

    func clear()
    func createBuffers() throws
    func descriptor() -> MTLAccelerationStructureGeometryDescriptor
    func resources()  -> [MTLResource]
}

class TriangleGeometry: Geometry {
    var device:                    MTLDevice
    var intersectionFunctionName = ""

    private var indexBuffer:            MTLBuffer!
    private var vertexPositionBuffer:   MTLBuffer!
    private var vertexNormalBuffer:     MTLBuffer!
    private var vertexColorBuffer:      MTLBuffer!
    private var perPrimitiveDataBuffer: MTLBuffer!

    private var indices   = [UInt16]()
    private var vertices  = [vector_float3]()
    private var normals   = [vector_float3]()
    private var colors    = [vector_float3]()
    private var triangles = [Triangle]()

    required init(device: MTLDevice) {
        self.device = device
    }

    func clear() {
        indices.removeAll()
        vertices.removeAll()
        normals.removeAll()
        colors.removeAll()
        triangles.removeAll()
    }

    func createBuffers() throws {
        indexBuffer = try device.makeBuffer(
            bytes: &indices,
            length: indices.count * MemoryLayout<UInt16>.stride,
            options: [.storageModeShared]) ?? {
                throw MTLContextError(.apiReturnedNil, userInfo: "makeBuffer")
            }()
        vertexPositionBuffer = try device.makeBuffer(
            bytes: &vertices,
            length: vertices.count * MemoryLayout<vector_float3>.stride,
            options: [.storageModeShared]) ?? {
                throw MTLContextError(.apiReturnedNil, userInfo: "makeBuffer")
            }()
        vertexNormalBuffer = try device.makeBuffer(
            bytes: &normals,
            length: normals.count * MemoryLayout<vector_float3>.stride,
            options: [.storageModeShared]) ?? {
                throw MTLContextError(.apiReturnedNil, userInfo: "makeBuffer")
            }()
        vertexColorBuffer = try device.makeBuffer(
            bytes: &colors,
            length: colors.count * MemoryLayout<vector_float3>.stride,
            options: [.storageModeShared]) ?? {
                throw MTLContextError(.apiReturnedNil, userInfo: "makeBuffer")
            }()
        perPrimitiveDataBuffer = try device.makeBuffer(
            bytes: &triangles,
            length: triangles.count * MemoryLayout<Triangle>.stride,
            options: [.storageModeShared]) ?? {
                throw MTLContextError(.apiReturnedNil, userInfo: "makeBuffer")
            }()
    }

    func descriptor() -> MTLAccelerationStructureGeometryDescriptor {
        let descriptor = MTLAccelerationStructureTriangleGeometryDescriptor()

        descriptor.indexBuffer = indexBuffer
        descriptor.indexType   = .uint16

        descriptor.vertexBuffer  = vertexPositionBuffer
        descriptor.vertexStride  = MemoryLayout<vector_float3>.stride
        descriptor.triangleCount = indices.count / 3

        descriptor.primitiveDataBuffer      = perPrimitiveDataBuffer
        descriptor.primitiveDataStride      = MemoryLayout<Triangle>.stride
        descriptor.primitiveDataElementSize = MemoryLayout<Triangle>.stride

        return descriptor
    }

    func resources() -> [MTLResource] {
        [indexBuffer, vertexNormalBuffer, vertexColorBuffer]
    }

    func addCube(withFaces mask: UInt, color: vector_float3, transform: matrix_float4x4, inwardNormals: Bool) {
        var vertices = [
            vector_float3(-0.5, -0.5, -0.5),
            vector_float3( 0.5, -0.5, -0.5),
            vector_float3(-0.5,  0.5, -0.5),
            vector_float3( 0.5,  0.5, -0.5),
            vector_float3(-0.5, -0.5,  0.5),
            vector_float3( 0.5, -0.5,  0.5),
            vector_float3(-0.5,  0.5,  0.5),
            vector_float3( 0.5,  0.5,  0.5)
        ]

        for i in 0..<8 {
            let vertex = vertices[i]

            var transformedVertex = simd_make_float4(vertex, 1.0)
            transformedVertex     = transform * transformedVertex

            vertices[i] = simd_make_float3(transformedVertex)
        }

        let indices: [[UInt16]] = [
            [0, 4, 6, 2],
            [1, 3, 7, 5],
            [0, 1, 5, 4],
            [2, 6, 7, 3],
            [0, 2, 3, 1],
            [4, 5, 7, 6]
        ]

        for face in 0..<6 {
            if mask & (1 << face) > 0 {
                addCubeFace(
                    withVertices: vertices,
                    color: color,
                    i0: indices[face][0], i1: indices[face][1],
                    i2: indices[face][2], i3: indices[face][3],
                    inwardNormals: inwardNormals)
            }
        }
    }

    private func addCubeFace(withVertices list: [vector_float3], color: vector_float3, i0: UInt16, i1: UInt16, i2: UInt16, i3: UInt16, inwardNormals: Bool) {
        let v0 = list[Int(i0)]
        let v1 = list[Int(i1)]
        let v2 = list[Int(i2)]
        let v3 = list[Int(i3)]

        var n0 = getTriangleNormal(v0, v1, v2)
        var n1 = getTriangleNormal(v0, v2, v3)

        if inwardNormals {
            n0 = -n0
            n1 = -n1
        }

        let firstIndex = indices.count

        let baseIndex = UInt16(vertices.count)
        indices.append(baseIndex + 0)
        indices.append(baseIndex + 1)
        indices.append(baseIndex + 2)
        indices.append(baseIndex + 0)
        indices.append(baseIndex + 2)
        indices.append(baseIndex + 3)

        vertices.append(v0)
        vertices.append(v1)
        vertices.append(v2)
        vertices.append(v3)

        normals.append(simd_normalize(n0 + n1))
        normals.append(n0)
        normals.append(simd_normalize(n0 + n1))
        normals.append(n1)

        for _ in 0..<4 {
            colors.append(color)
        }

        for triangleIndex in 0..<2 {
            var triangle = Triangle()
            for i in 0..<3 {
                let index = Int(indices[firstIndex + triangleIndex * 3 + i])
                // https://stackoverflow.com/a/65500187
                withUnsafeMutablePointer(to: &triangle.normals) { tuple in
                    tuple.withMemoryRebound(to: vector_float3.self, capacity: 3) { array in
                        array[i] = normals[index]
                    }
                }
                withUnsafeMutablePointer(to: &triangle.colors) { tuple in
                    tuple.withMemoryRebound(to: vector_float3.self, capacity: 3) { array in
                        array[i] = colors[index]
                    }
                }
            }
            triangles.append(triangle)
        }
    }
}

class SphereGeometry: Geometry {
    var device:                    MTLDevice
    var intersectionFunctionName = "sphereIntersectionFunction"

    private var sphereBuffer:      MTLBuffer!
    private var boundingBoxBuffer: MTLBuffer!

    private var spheres = [Sphere]()

    required init(device: MTLDevice) {
        self.device = device
    }

    func clear() {
        spheres.removeAll()
    }

    func createBuffers() throws {
        var boundingBoxes = [BoundingBox]()

        for sphere in spheres {
            var bounds = BoundingBox()

            bounds.min.x = sphere.origin.x - sphere.radius
            bounds.min.y = sphere.origin.y - sphere.radius
            bounds.min.z = sphere.origin.z - sphere.radius

            bounds.max.x = sphere.origin.x + sphere.radius
            bounds.max.y = sphere.origin.y + sphere.radius
            bounds.max.z = sphere.origin.z + sphere.radius

            boundingBoxes.append(bounds)
        }

        sphereBuffer = try device.makeBuffer(
            bytes: &spheres,
            length: spheres.count * MemoryLayout<Sphere>.stride,
            options: [.storageModeShared]) ?? {
                throw MTLContextError(.apiReturnedNil, userInfo: "makeBuffer")
            }()
        boundingBoxBuffer = try device.makeBuffer(
            bytes: &boundingBoxes,
            length: spheres.count * MemoryLayout<BoundingBox>.stride,
            options: [.storageModeShared]) ?? {
                throw MTLContextError(.apiReturnedNil, userInfo: "makeBuffer")
            }()
    }

    func descriptor() -> MTLAccelerationStructureGeometryDescriptor {
        let descriptor = MTLAccelerationStructureBoundingBoxGeometryDescriptor()

        descriptor.boundingBoxBuffer = boundingBoxBuffer
        descriptor.boundingBoxCount  = spheres.count

        descriptor.primitiveDataBuffer      = sphereBuffer
        descriptor.primitiveDataStride      = MemoryLayout<Sphere>.stride
        descriptor.primitiveDataElementSize = MemoryLayout<Sphere>.stride

        return descriptor
    }

    func resources() -> [MTLResource] {
        [sphereBuffer]
    }

    func addSphere(withOrigin origin: vector_float3, radius: Float, color: vector_float3) {
        let sphere = Sphere(
            origin: MTLPackedFloat3(origin),
            radiusSquared: radius * radius,
            color: MTLPackedFloat3(color),
            radius: radius)
        spheres.append(sphere)
    }
}

class GeometryInstance: NSObject {
    private(set) var geometry: Geometry
    private(set) var transform: matrix_float4x4
    private(set) var mask: UInt32

    init(geometry: Geometry, transform: matrix_float4x4, mask: UInt32) {
        self.geometry  = geometry
        self.transform = transform
        self.mask      = mask
    }
}

enum LineUp {
    case oneByOne
    case twoByTwo
    case threeByThree
}

class Stage {
    var viewerStandingAtLocation = vector_float3(0.0, 0.0, 1.0)
    var viewerLookingAtLocation  = vector_float3(0.0, 0.0, 0.0)
    var viewerHeadingUpDirection = vector_float3(0.0, 1.0, 0.0)

    private(set) var device: MTLDevice

    private(set) var geometries: NSMutableArray = []
    private(set) var instances = [GeometryInstance]()

    private var lights = [AreaLight]()
    private(set) var lightBuffer: MTLBuffer!
    var lightCount: UInt32 { UInt32(lights.count) }

    init(device: MTLDevice) {
        self.device = device
    }

    class func hoistCornellBox(lineUp: LineUp = .threeByThree, device: MTLDevice) -> Stage {
        let stage = Stage(device: device)

        let lightMesh = TriangleGeometry(device: device)
        stage.addGeometry(geometry: lightMesh)

        var transform = matrix4x4_translation(0.0, 1.0, 0.0) * matrix4x4_scale(0.5, 1.98, 0.5)

        lightMesh.addCube(
            withFaces: FACE_MASK_POSITIVE_Y,
            color: vector_float3(1.0, 1.0, 1.0),
            transform: transform,
            inwardNormals: true)

        let geometryMesh = TriangleGeometry(device: device)
        stage.addGeometry(geometry: geometryMesh)

        transform = matrix4x4_translation(0.0, 1.0, 0.0) * matrix4x4_scale(2.0, 2.0, 2.0)

        geometryMesh.addCube(
            withFaces: FACE_MASK_NEGATIVE_Y | FACE_MASK_POSITIVE_Y | FACE_MASK_NEGATIVE_Z,
            color: vector_float3(0.725, 0.71, 0.68),
            transform: transform,
            inwardNormals: true)
        geometryMesh.addCube(
            withFaces: FACE_MASK_NEGATIVE_X,
            color: vector_float3(0.63, 0.065, 0.05),
            transform: transform,
            inwardNormals: true)
        geometryMesh.addCube(
            withFaces: FACE_MASK_POSITIVE_X,
            color: vector_float3(0.14, 0.45, 0.091),
            transform: transform,
            inwardNormals: true)

        transform = matrix4x4_translation(-0.335, 0.6, -0.29) * matrix4x4_rotation(radians: 0.3, axis: vector_float3(0.0, 1.0, 0.0)) * matrix4x4_scale(0.6, 1.2, 0.6)

        geometryMesh.addCube(
            withFaces: FACE_MASK_ALL,
            color: vector_float3(0.725, 0.71, 0.68),
            transform: transform,
            inwardNormals: false)

        let sphereGeometry = SphereGeometry(device: device)
        stage.addGeometry(geometry: sphereGeometry)

        sphereGeometry.addSphere(
            withOrigin: vector_float3(0.3275, 0.3, 0.3725),
            radius: 0.3,
            color: vector_float3(0.725, 0.71, 0.68))

        let hoistInstances = { (_ x: Float, _ y: Float) -> () in
            transform = matrix4x4_translation(x * 2.5, y * 2.5, 0.0)

            let lightMeshInstance = GeometryInstance(
                geometry: lightMesh,
                transform: transform,
                mask: GEOMETRY_MASK_LIGHT)
            stage.addGeometryInstance(instance: lightMeshInstance)

            let geometryMeshInstance = GeometryInstance(
                geometry: geometryMesh,
                transform: transform,
                mask: GEOMETRY_MASK_TRIANGLE)
            stage.addGeometryInstance(instance: geometryMeshInstance)

            let sphereGeometryInstance = GeometryInstance(
                geometry: sphereGeometry,
                transform: transform,
                mask: GEOMETRY_MASK_SPHERE)
            stage.addGeometryInstance(instance: sphereGeometryInstance)

            let r = Float.random(in: 0.0...1.0)
            let g = Float.random(in: 0.0...1.0)
            let b = Float.random(in: 0.0...1.0)

            let areaLight = AreaLight(
                position: vector_float3(x * 2.5, y * 2.5 + 1.98, 2.0),
                forward: vector_float3(0.0, -1.0, 0.0),
                right: vector_float3(0.25, 0.0, 0.0),
                up: vector_float3(0.0, 0.0, 0.25),
                color: vector_float3(r * 4, g * 4, b * 4))
            stage.addLight(light: areaLight)
        }

        switch lineUp {
        case .oneByOne:
            stage.viewerStandingAtLocation = vector_float3(0.0, 0.0, 5.0)
            hoistInstances(0.0, 0.0)
        case .twoByTwo:
            stage.viewerStandingAtLocation = vector_float3(0.0, 0.0, 8.5)
            hoistInstances(-0.5, -0.5)
            hoistInstances( 0.5, -0.5)
            hoistInstances(-0.5,  0.5)
            hoistInstances( 0.5,  0.5)
        case .threeByThree:
            stage.viewerStandingAtLocation = vector_float3(0.0, 0.0, 12.0)
            for y in -1...1 {
                for x in -1...1 {
                    hoistInstances(Float(x), Float(y))
                }
            }
        }

        return stage
    }

    func clear() {
        geometries.removeAllObjects()
        instances.removeAll()
        lights.removeAll()
    }

    func createBuffers() throws {
        for geometry in geometries {
            try (geometry as! Geometry).createBuffers()
        }

        lightBuffer = device.makeBuffer(
            bytes: &lights,
            length: lights.count * MemoryLayout<AreaLight>.stride,
            options: [.storageModeShared])
    }

    func addGeometry(geometry: Geometry) {
        geometries.add(geometry)
    }

    func addGeometryInstance(instance: GeometryInstance) {
        instances.append(instance)
    }

    func addLight(light: AreaLight) {
        lights.append(light)
    }
}

extension MTLPackedFloat3 {
    init(_ vector: vector_float3) {
        self.init()
        self.elements = (vector[0], vector[1], vector[2])
    }
}
