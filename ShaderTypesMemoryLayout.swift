import MetalKit
import simd

print(String(format: "vector_float3: %d, %d", MemoryLayout<vector_float3>.size, MemoryLayout<vector_float3>.stride))
print(String(format: "MTLPackedFloat3: %d, %d", MemoryLayout<MTLPackedFloat3>.size, MemoryLayout<MTLPackedFloat3>.stride))
print(String(format: "  x: %d, %d", MemoryLayout<Float>.size, MemoryLayout<Float>.stride))
print(String(format: "  y: %d, %d", MemoryLayout<Float>.size, MemoryLayout<Float>.stride))
print(String(format: "  z: %d, %d", MemoryLayout<Float>.size, MemoryLayout<Float>.stride))
print(String(format: "Camera: %d, %d", MemoryLayout<Camera>.size, MemoryLayout<Camera>.stride))
print(String(format: "  position: %d, %d", MemoryLayout<vector_float3>.size, MemoryLayout<vector_float3>.stride))
print(String(format: "  right:    %d, %d", MemoryLayout<vector_float3>.size, MemoryLayout<vector_float3>.stride))
print(String(format: "  up:       %d, %d", MemoryLayout<vector_float3>.size, MemoryLayout<vector_float3>.stride))
print(String(format: "  forward:  %d, %d", MemoryLayout<vector_float3>.size, MemoryLayout<vector_float3>.stride))
print(String(format: "AreaLight: %d, %d", MemoryLayout<AreaLight>.size, MemoryLayout<AreaLight>.stride))
print(String(format: "  position: %d, %d", MemoryLayout<vector_float3>.size, MemoryLayout<vector_float3>.stride))
print(String(format: "  forward:  %d, %d", MemoryLayout<vector_float3>.size, MemoryLayout<vector_float3>.stride))
print(String(format: "  right:    %d, %d", MemoryLayout<vector_float3>.size, MemoryLayout<vector_float3>.stride))
print(String(format: "  up:       %d, %d", MemoryLayout<vector_float3>.size, MemoryLayout<vector_float3>.stride))
print(String(format: "  color:    %d, %d", MemoryLayout<vector_float3>.size, MemoryLayout<vector_float3>.stride))
print(String(format: "Uniforms: %d, %d", MemoryLayout<Uniforms>.size, MemoryLayout<Uniforms>.stride))
print(String(format: "  width:      %d, %d", MemoryLayout<UInt32>.size, MemoryLayout<UInt32>.stride))
print(String(format: "  heigth:     %d, %d", MemoryLayout<UInt32>.size, MemoryLayout<UInt32>.stride))
print(String(format: "  frameIndex: %d, %d", MemoryLayout<UInt32>.size, MemoryLayout<UInt32>.stride))
print(String(format: "  lightCount: %d, %d", MemoryLayout<UInt32>.size, MemoryLayout<UInt32>.stride))
print(String(format: "  camera: %d, %d", MemoryLayout<Camera>.size, MemoryLayout<Camera>.stride))
print(String(format: "    position: %d, %d", MemoryLayout<vector_float3>.size, MemoryLayout<vector_float3>.stride))
print(String(format: "    right:    %d, %d", MemoryLayout<vector_float3>.size, MemoryLayout<vector_float3>.stride))
print(String(format: "    up:       %d, %d", MemoryLayout<vector_float3>.size, MemoryLayout<vector_float3>.stride))
print(String(format: "    forward:  %d, %d", MemoryLayout<vector_float3>.size, MemoryLayout<vector_float3>.stride))
print(String(format: "Sphere: %d, %d", MemoryLayout<Sphere>.size, MemoryLayout<Sphere>.stride))
print(String(format: "  origin:        %d, %d", MemoryLayout<MTLPackedFloat3>.size, MemoryLayout<MTLPackedFloat3>.stride))
print(String(format: "  radiusSquared: %d, %d", MemoryLayout<Float>.size, MemoryLayout<Float>.stride))
print(String(format: "  color:         %d, %d", MemoryLayout<MTLPackedFloat3>.size, MemoryLayout<MTLPackedFloat3>.stride))
print(String(format: "  radius:        %d, %d", MemoryLayout<Float>.size, MemoryLayout<Float>.stride))
print(String(format: "Triangle: %d, %d", MemoryLayout<Triangle>.size, MemoryLayout<Triangle>.stride))
print(String(format: "  normals: %d, %d",
    MemoryLayout<(vector_float3, vector_float3, vector_float3)>.size,
    MemoryLayout<(vector_float3, vector_float3, vector_float3)>.stride))
print(String(format: "  colors:  %d, %d",
    MemoryLayout<(vector_float3, vector_float3, vector_float3)>.size,
    MemoryLayout<(vector_float3, vector_float3, vector_float3)>.stride))

struct Camera {
    var position: vector_float3
    var right:    vector_float3
    var up:       vector_float3
    var forward:  vector_float3
}

struct AreaLight {
    var position: vector_float3
    var forward:  vector_float3
    var right:    vector_float3
    var up:       vector_float3
    var color:    vector_float3
}

struct Uniforms {
    var width:      UInt32
    var height:     UInt32
    var frameIndex: UInt32
    var lightCount: UInt32
    var camera:     Camera
}

struct Sphere {
    var origin:        MTLPackedFloat3
    var radiusSquared: Float
    var color:         MTLPackedFloat3
    var radius:        Float
}

struct Triangle {
    var normals: (vector_float3, vector_float3, vector_float3)
    var colors:  (vector_float3, vector_float3, vector_float3)
}
