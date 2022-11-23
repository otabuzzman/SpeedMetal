import simd

let GEOMETRY_MASK_TRIANGLE = 1
let GEOMETRY_MASK_SPHERE   = 2
let GEOMETRY_MASK_LIGHT    = 4

let GEOMETRY_MASK_GEOMETRY = (GEOMETRY_MASK_TRIANGLE | GEOMETRY_MASK_SPHERE)

let RAY_MASK_PRIMARY       = (GEOMETRY_MASK_GEOMETRY | GEOMETRY_MASK_LIGHT)
let RAY_MASK_SHADOW        = GEOMETRY_MASK_GEOMETRY
let RAY_MASK_SECONDARY     = GEOMETRY_MASK_GEOMETRY

struct packed_float3 {
    var x: Float
    var y: Float
    var z: Float
}

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
    var width:      UInt
    var height:     UInt
    var frameIndex: Int
    var lightCount: UInt
    var camera:     Camera
}

struct Sphere {
    var origin:        packed_float3
    var radiusSquared: Float
    var color:         packed_float3
    var radius:        Float
}

struct Triangle {
    var normals: [vector_float3, vector_float3, vector_float3]
    var colors:  [vector_float3, vector_float3, vector_float3]
}
