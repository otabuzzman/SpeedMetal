import MetalKit
import simd

let GEOMETRY_MASK_TRIANGLE: UInt32 = 1
let GEOMETRY_MASK_SPHERE: UInt32   = 2
let GEOMETRY_MASK_LIGHT: UInt32    = 4

let GEOMETRY_MASK_GEOMETRY: UInt32 = GEOMETRY_MASK_TRIANGLE | GEOMETRY_MASK_SPHERE

let RAY_MASK_PRIMARY: UInt32       = GEOMETRY_MASK_GEOMETRY | GEOMETRY_MASK_LIGHT
let RAY_MASK_SHADOW: UInt32        = GEOMETRY_MASK_GEOMETRY
let RAY_MASK_SECONDARY: UInt32     = GEOMETRY_MASK_GEOMETRY

struct Camera {
    var position: vector_float3
    var forward:  vector_float3
    var right:    vector_float3
    var up:       vector_float3
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

    init() {
        normals = (.zero, .zero, .zero)
        colors  = (.zero, .zero, .zero)
    }
}
