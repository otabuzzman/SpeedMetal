/*
 * g++ -I"$(cygpath -w '/cygdrive/c/program files/nvidia gpu computing toolkit/cuda/v11.4/include')" ShaderTypesMemoryLayout.cpp -o ShaderTypesMemoryLayout.exe ; ./ShaderTypesMemoryLayout
 */

#include <stdio.h>
#include <stddef.h>

#include "cuda_runtime.h"
#ifndef __METAL_VERSION__
struct packed_float3 {
#ifdef __cplusplus
    packed_float3() = default;
    packed_float3(float3 v) : x(v.x), y(v.y), z(v.z) {}
#endif
    float x;
    float y;
    float z;
};
#endif

struct Camera {
    float3 position;
    float3 right;
    float3 up;
    float3 forward;
};

struct AreaLight {
    float3 position;
    float3 forward;
    float3 right;
    float3 up;
    float3 color;
};

struct Uniforms {
    unsigned int width;
    unsigned int height;
    unsigned int frameIndex;
    unsigned int lightCount;
    Camera camera;
};

struct Sphere {
    packed_float3 origin;
    float radiusSquared;
    packed_float3 color;
    float radius;
};

struct Triangle {
    float3 normals[3];
    float3 colors[3];
};

int main() {
    printf("float3: %d\n", sizeof(float3));
    printf("packed_float3: %d\n", sizeof(packed_float3));
    printf("  x: %d\n", offsetof(struct packed_float3, x));
    printf("  y: %d\n", offsetof(struct packed_float3, y));
    printf("  z: %d\n", offsetof(struct packed_float3, z));
    printf("Camera: %d\n", sizeof(Camera));
    printf("  position: %d\n", offsetof(struct Camera, position));
    printf("  right:    %d\n", offsetof(struct Camera, right));
    printf("  up:       %d\n", offsetof(struct Camera, up));
    printf("  forward:  %d\n", offsetof(struct Camera, forward));
    printf("AreaLight: %d\n", sizeof(AreaLight));
    printf("  position: %d\n", offsetof(struct AreaLight, position));
    printf("  forward:  %d\n", offsetof(struct AreaLight, forward));
    printf("  right:    %d\n", offsetof(struct AreaLight, right));
    printf("  up:       %d\n", offsetof(struct AreaLight, up));
    printf("  color:    %d\n", offsetof(struct AreaLight, color));
    printf("Uniforms: %d\n", sizeof(Uniforms));
    printf("  width:      %d\n", offsetof(struct Uniforms, width));
    printf("  heigth:     %d\n", offsetof(struct Uniforms, height));
    printf("  frameIndex: %d\n", offsetof(struct Uniforms, frameIndex));
    printf("  lightCount: %d\n", offsetof(struct Uniforms, lightCount));
    int cameraStart = offsetof(struct Uniforms, camera);
    printf("  camera: %d\n", offsetof(struct Uniforms, camera));
    printf("    position: %d\n", cameraStart + offsetof(struct Camera, position));
    printf("    right:    %d\n", cameraStart + offsetof(struct Camera, right));
    printf("    up:       %d\n", cameraStart + offsetof(struct Camera, up));
    printf("    forward:  %d\n", cameraStart + offsetof(struct Camera, forward));
    printf("Sphere: %d\n", sizeof(Sphere));
    printf("  origin:        %d\n", offsetof(struct Sphere, origin));
    printf("  radiusSquared: %d\n", offsetof(struct Sphere, radiusSquared));
    printf("  color:         %d\n", offsetof(struct Sphere, color));
    printf("  radius:        %d\n", offsetof(struct Sphere, radius));
    printf("Triangle: %d\n", sizeof(Triangle));
    printf("  normals: %d\n", offsetof(struct Triangle, normals));
    printf("  colors:  %d\n", offsetof(struct Triangle, colors));
}
