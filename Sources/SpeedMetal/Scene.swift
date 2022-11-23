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

func getManagedBufferStorageMode() -> MTLResourceOptions {
    if !UIDevice.current.userInterfaceIdiom == .phone {
        return MTLResourceStorageModeManaged
    } else {
        return MTLResourceStorageModeShared
    }
}

func getTriangleNormal(_ v0: float3, _ v1: float3, _ v2: float3 ) -> float3 {
    e1: float3 = normalize(v1 - v0)
    e2: float3 = normalize(v2 - v0)

    return cross(e1, e2)
}

protocol Geometry: NSObject {
    var device:                   MTLDevice { get }
    var intersectionFunctionName: NSString  { get }

    init(device: MTLDevice) // initWithDevice

    func clear() -> Void
    func uploadToBuffers() -> Void
    func geometryDescriptor() -> MTLAccelerationStructureGeometryDescriptor
    func resources() -> [MTLResource]
}

class TriangleGeometry: Geometry {
    var device:                   MTLDevice
    var intersectionFunctionName: NSString { "" }

    private var indexBuffer:            MTLBuffer
    private var vertexPositionBuffer:   MTLBuffer
    private var vertexNormalBuffer:     MTLBuffer
    private var vertexColorBuffer:      MTLBuffer
    private var perPrimitiveDataBuffer: MTLBuffer

    private var indices:   [UInt16]        = []
    private var vertices:  [vector_float3] = []
    private var normals:   [vector_float3] = []
    private var colors:    [vector_float3] = []
    private var triangles: [Triangle]      = []

    init(device: MTLDevice) {
        super.init()
        self.device = device
    }

    func clear() {
        indices.removeAll()
        vertices.removeAll()
        normals.removeAll()
        colors.removeAll()
        triangles.removeAll()
    }

    func uploadToBuffers() -> Void {
        let options = getManagedBufferStorageMode()

        let device = self.device

        indexBuffer            = device!.makeBuffer(bytes: sphereBuffer,   length: sphereBuffer.count*MemoryLayout<Sphere>.stride, options: options)!
        vertexPositionBuffer   = device!.makeBuffer(bytes: vertices,  length: vertices.count*MemoryLayout<vector_float3>.stride, options: options)!
        vertexNormalBuffer     = device!.makeBuffer(bytes: normals,   length: normals.count*MemoryLayout<vector_float3>.stride, options: options)!
        vertexColorBuffer      = device!.makeBuffer(bytes: colors,    length: colors.count*MemoryLayout<vector_float3>.stride, options: options)!
        perPrimitiveDataBuffer = device!.makeBuffer(bytes: triangles, length: triangles.count*MemoryLayout<Triangle>.stride, options: options)!

        if !UIDevice.current.userInterfaceIdiom == .phone {
            indexBuffer.didModifyRange(0..<indexBuffer.count)
            vertexPositionBuffer.didModifyRange(0..<vertexPositionBuffer.count)
            vertexNormalBuffer.didModifyRange(0..<vertexNormalBuffer.count)
            vertexColorBuffer.didModifyRange(0..<vertexColorBuffer.count)
            perPrimitiveDataBuffer.didModifyRange(0..<perPrimitiveDataBuffer.count)
        }
    }

    func geometryDescriptor() -> MTLAccelerationStructureGeometryDescriptor {
        let descriptor = MTLAccelerationStructureTriangleGeometryDescriptor()

        descriptor.indexBuffer = indexBuffer
        descriptor.indexType = .uint16

        descriptor.vertexBuffer = vertexPositionBuffer
        descriptor.vertexStride = MemoryLayout<float3>.stride
        descriptor.triangleCount = indices.count / 3

        // Metal 3
        if #available(iOS 16, macOS 13, *) {
            descriptor.primitiveDataBuffer = perPrimitiveDataBuffer
            descriptor.primitiveDataStride = MemoryLayout<Triangle>.stride
            descriptor.primitiveDataElementSize = MemoryLayout<Triangle>.stride
        }

        return descriptor
    }

    func resources() -> [MTLResource] {
        [indexBuffer, vertexNormalBuffer, vertexColorBuffer]
    }

    private func addCubeWithFaces(faceMask: UInt, color: vector_float3, transform: matrix_float4x4, inwardNormals: Bool) -> Void {
        let cubeVertices = [
            vector3(-0.5, -0.5, -0.5),
            vector3( 0.5, -0.5, -0.5),
            vector3(-0.5,  0.5, -0.5),
            vector3( 0.5,  0.5, -0.5),
            vector3(-0.5, -0.5,  0.5),
            vector3( 0.5, -0.5,  0.5),
            vector3(-0.5,  0.5,  0.5),
            vector3( 0.5,  0.5,  0.5)
        ]

        for i in 0..<8 {
            let vertex = cubeVertices[i]

            let transformedVertex = vector4(vertex.x, vertex.y, vertex.z, 1.0f)
            transformedVertex = transform * transformedVertex

            cubeVertices[i] = transformedVertex.xyz
        }

        let cubeIndices: [[UInt16]] = [
            [0, 4, 6, 2],
            [1, 3, 7, 5],
            [0, 1, 5, 4],
            [2, 6, 7, 3],
            [0, 2, 3, 1],
            [4, 5, 7, 6]
        ]

        for face in 0..<6 {
            if faceMask & (1 << face) {
                addCubeFaceWithCubeVertices(cubeVertices: cubeVertices, color: color, i0: cubeIndices[face][0], i1: cubeIndices[face][0], i2: cubeIndices[face][0], i3: cubeIndices[face][0], inwardNormals: inwardNormals)
            }
        }
    }

    private func addCubeFaceWithCubeVertices(cubeVertices: [float3], color: float3, i0: UInt16, i1: UInt16, i2: UInt16, i3: UInt16, inwardNormals: Bool) -> Void {
        let v0 = cubeVertices[i0]
        let v1 = cubeVertices[i1]
        let v2 = cubeVertices[i2]
        let v3 = cubeVertices[i3]

        let n0 = getTriangleNormal(v0, v1, v2)
        let n1 = getTriangleNormal(v0, v2, v3)

        if inwardNormals {
            n0 = -n0
            n1 = -n1
        }

        let firstIndex = indices.count

        let baseIndex = vertices.count
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

        normals.append(normalize(n0 + n1))
        normals.append(n0)
        normals.append(normalize(n0 + n1))
        normals.append(n1)

        for i in 0..<4 {
            colors.append(color)
        }

        for triangleIndex in 0..<2 {
            for i in 0..<3 {
                let triangle = Triangle()
                let index = indices[firstIndex + triangleIndex * 3 + i]
                triangle.normals[i] = normals[index]
                triangle.colors[i] = colors[index]
            }
            triangles.append(triangle)
        }
    }
}

class SphereGeometry: Geometry {
    var device:                   MTLDevice
    var intersectionFunctionName: NSString { "sphereIntersectionFunction" }

    private var sphereBuffer:           MTLBuffer
    private var boundingBoxBuffer:      MTLBuffer
    private var perPrimitiveDataBuffer: MTLBuffer

    private var spheres: [Sphere] = []

    init(device: MTLDevice) {
        super.init()
        self.device = device
    }

    func clear() {
        spheres.removeAll()
    }

    func uploadToBuffers() -> Void {
        let options = getManagedBufferStorageMode()

        let device = self.device

        var boundingBoxes: [BoundingBox]

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

        sphereBuffer      = device!.makeBuffer(bytes: spheres, length: spheres.count*MemoryLayout<Sphere>.stride, options: options)!
        boundingBoxBuffer = device!.makeBuffer(bytes: boundingBoxes, length: spheres.count*MemoryLayout<BoundingBox>.stride, options: options)!


        if !UIDevice.current.userInterfaceIdiom == .phone {
            sphereBuffer.didModifyRange(0..<sphereBuffer.count)
            boundingBoxBuffer.didModifyRange(0..<boundingBoxBuffer.count)
        }
    }

    func geometryDescriptor() -> MTLAccelerationStructureGeometryDescriptor {
        let descriptor = MTLAccelerationStructureTriangleGeometryDescriptor()

        descriptor.boundingBoxBuffer = boundingBoxBuffer
        descriptor.boundingBoxCount = spheres.count

        // Metal 3
        if #available(iOS 16, macOS 13, *) {
            descriptor.primitiveDataBuffer = sphereBuffer
            descriptor.primitiveDataStride = MemoryLayout<Sphere>.stride
            descriptor.primitiveDataElementSize = MemoryLayout<Sphere>.stride
        }

        return descriptor
    }

    func resources() -> [MTLResource] {
        [sphereBuffer]
    }

    private func addSphereWithOrigin(origin: vector_float3, radius: Float, color: vector_float3) -> Void {
        let sphere = Sphere()

        sphere.origin = origin
        sphere.radiusSquared = radius * radius
        sphere.color = color
        sphere.radius = radius

        spheres.append(sphere)
    }
}

class GeometryInstance: NSObject {
    private(set) var geometry: Geometry
    private(set) var transform: matrix_float4x4
    private(set) var mask: UInt

    init(geometry: Geometry, transform: matrix_float4x4, mask: UInt) { // initWithGeometry
        self.geometry = geometry
        self.transform = transform
        self.mask = mask
    }
}

class Scene: NSObject {
    private(set) var device:      MTLDevice
    private(set) var geometries:  [Geometry]
    private(set) var instances:   [GeometryInstance]
    private(set) var lightBuffer: MTLBuffer
    private(set) var lightCount:  NSUInteger

    private var cameraPosition: vector_float3
    private var cameraTarget:   vector_float3
    private var cameraUp:       vector_float3

    private var geometries = [Geometry]
    private var instances  = [GeometryInstance]

    private var lights: [AreaLight] = []

    init(device: MTLDevice) { // initWithDevice
        self.device = device

        cameraPosition = vector3(0.0, 0.0, -1.0)
        cameraTarget   = vector3(0.0, 0.0, 0.0)
        cameraUp       = vector3(0.0, 1.0, 0.0)
    }

    class func newInstancedCornellBoxSceneWithDevice(device: MTLDevice, useIntersectionFunctions: Bool) -> Scene {
        var scene = Scene(device: device)

        scene.cameraPosition = vector3(0.0, 1.0, 10.0)
        scene.cameraTarget   = vector3(0.0, 1.0, 0.0)
        scene.cameraUp       = vector3(0.0, 1.0, 0.0)

        let lightMesh = TriangleGeometry(device: device)
        scene.addGeometry(mesh: lightMesh)

        var transform = matrix4x4_translation(0.0, 1.0, 0.0) * matrix4x4_scale(0.5, 1.98, 0.5)
        lightMesh.addCubeWithFaces(faceMask: FACE_MASK_POSITIVE_Y, color: vector3(1.0, 1.0, 1.0), transform: transform, inwardNormals: true)

        let geometryMesh = TriangleGeometry(device: device)
        scene.addGeometry(mesh: geometryMesh)

        transform = matrix4x4_translation(0.0, 1.0, 0.0) * matrix4x4_scale(2.0, 2.0, 2.0)

        geometryMesh.addCubeWithFaces(faceMask: FACE_MASK_NEGATIVE_Y | FACE_MASK_POSITIVE_Y | FACE_MASK_NEGATIVE_Z, color: vector3(0.725, 0.71, 0.68), transform: transform, inwardNormals: true)
        geometryMesh.addCubeWithFaces(faceMask: FACE_MASK_NEGATIVE_X, color: vector3(0.63, 0.065, 0.05), transform: transform, inwardNormals: true)
        geometryMesh.addCubeWithFaces(faceMask: FACE_MASK_NEGATIVE_X, color: vector3(0.14, 0.45, 0.091), transform: transform, inwardNormals: true)

        transform = matrix4x4_translation(-0.335, 0.6, -0.29) * matrix4x4_rotation(0.3, vector3(0.0, 1.0, 0.0)) * matrix4x4_scale(0.6, 1.2, 0.6)

        geometryMesh.addCubeWithFaces(faceMask: FACE_MASK_ALL, color: vector3(0.725, 0.71, 0.68), transform: transform, inwardNormals: false)

        var sphereGeometry: SphereGeometry?

        if !useIntersectionFunctions {
            transform = matrix4x4_translation(0.3275, 0.3, 0.3725) * matrix4x4_rotation(-0.3, vector3(0.0, 1.0, 0.0)) * matrix4x4_scale(0.6, 0.6, 0.6)

            geometryMesh.addCubeWithFaces(faceMask: FACE_MASK_ALL, color: vector3(0.725, 0.71, 0.68), transform: transform, inwardNormals: false)
        } else {
            sphereGeometry = SphereGeometry(device: device)
            sphereGeometry.addSphereWithOrigin(origin: vector3(0.3275, 0.3, 0.3725), radius: 0.3, color: vector3(0.725, 0.71, 0.68))

            scene.addGeometry(mesh: sphereGeometry)
        }

        // nine instances
        for y in -1...1 {
            for x in -1...1 {
                transform = matrix4x4_translation(x * 2.5, y * 2.5, 0.0)

                let lightMeshInstance = GeometryInstance(geometry: lightMesh, transform: transform, mask: GEOMETRY_MASK_LIGHT)
                scene.addInstance(instance: lightMeshInstance)

                let geometryMeshInstance = GeometryInstance(geometry: geometryMesh, transform: transform, mask: GEOMETRY_MASK_TRIANGLE)
                scene.addInstance(instance: geometryMeshInstance)

                if (useIntersectionFunctions) {
                    let sphereGeometryInstance = GeometryInstance(geometry: sphereGeometry!, transform: transform, mask: GEOMETRY_MASK_SPHERE)
                    scene.addInstance(instance: sphereGeometryInstance)
                }

                var light = AreaLight()

                light.position = vector3(x * 2.5, y * 2.5 + 1.98, 0.0)
                light.forward = vector3(0.0, -1.0, 0.0)
                light.right = vector3(0.25, 0.0, 0.0)
                light.up = vector3(0.0, 0.0, 0.25)

                float r = Float.random(in: 0.0..<1.0)
                float g = Float.random(in: 0.0..<1.0)
                float b = Float.random(in: 0.0..<1.0)

                light.color = vector3(r * 4.0, g * 4.0, b * 4.0)

                scene.addLight(light: light)
            }
        }

        return scene
    }

    func clear() -> Void {
        geometries.removeAll()
        instances.removeAll()

        lights.removeAll()
    }

    func uploadToBuffers() -> Void {
        for geometry in geometries {
            geometry.uploadToBuffers()
        }

        let options = getManagedBufferStorageMode()

        lightBuffer = device!.makeBuffer(bytes: lights, length: lights.count*MemoryLayout<AreaLight>.stride, options: options)!

        if !UIDevice.current.userInterfaceIdiom == .phone {
            lightBuffer.didModifyRange(0..<lightBuffer.count)
        }
    }

    func addGeometry(mesh: Geometry) -> Void {
        geometries.append(mesh)
    }

    func addInstance(instance: GeometryInstance) -> Void {
        instances.append(instance)
    }

    func addLight(light: AreaLight) -> Void {
        lights.append(light)
    }

    func geometries() -> [Geometry] {
        geometries
    }

    func lightCount() -> UInt {
        lights.count
    }
}
