import simd

func matrix4x4_translation(tx: Float, ty: Float, tz: Float) -> matrix_float4x4 {
    matrix_float4x4(rows: [
        [1, 0, 0, 0],
        [0, 1, 0, 0],
        [0, 0, 1, 0],
        [tx, ty, tz, 1]
    ])
}

func matrix4x4_rotation(radians: Float, axis: vector_float3) -> matrix_float4x4 {
    let axis = normalize(axis)
    let ct = cosf(radians)
    let st = sinf(radians)
    let ci = 1.0 - ct
    let x = axis.x, y = axis.y, z = axis.z
    
    let r0 = ct + x * x * ci,     r1 = y * x * ci + z * st, r2 = z * x * ci - y * st
    let r3 = x * y * ci - z * st, r4 = ct + y * y * ci,     r5 = z * y * ci + x * st
    let r6 = x * z * ci + y * st, r7 = y * z * ci - x * st, r8 = ct + z * z * ci

    return matrix_float4x4(rows: [
        [r0, r1, r2, 0],
        [r3, r4, r5, 0],
        [r6, r7, r8, 0],
        [0, 0, 0, 1]
    ])
}

func matrix4x4_scale(sx: Float, sy: Float, sz: Float) -> matrix_float4x4 {
    matrix_float4x4(rows: [
        [sx, 0, 0, 0],
        [0, sy, 0, 0],
        [0, 0, sz, 0],
        [0, 0, 0, 1]
    ])
}
