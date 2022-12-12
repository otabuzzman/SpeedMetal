import MetalKit
import simd

let GEOMETRY_MASK_TRIANGLE: UInt32 = 1
let GEOMETRY_MASK_SPHERE: UInt32   = 2
let GEOMETRY_MASK_LIGHT: UInt32    = 4

let GEOMETRY_MASK_GEOMETRY: UInt32 = (GEOMETRY_MASK_TRIANGLE | GEOMETRY_MASK_SPHERE)

let RAY_MASK_PRIMARY: UInt32       = (GEOMETRY_MASK_GEOMETRY | GEOMETRY_MASK_LIGHT)
let RAY_MASK_SHADOW: UInt32        = GEOMETRY_MASK_GEOMETRY
let RAY_MASK_SECONDARY: UInt32     = GEOMETRY_MASK_GEOMETRY

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
	var radiusSquared: Float
	var radius:        Float
    var origin:        vector_float3
    var color:         vector_float3
}

struct Triangle {
	var n0: vector_float3
	var n1: vector_float3
	var n2: vector_float3
	var c0: vector_float3
	var c1: vector_float3
	var c2: vector_float3
}
