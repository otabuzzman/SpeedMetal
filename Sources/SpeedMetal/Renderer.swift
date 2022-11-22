import MetalKit
import simd

protocol Renderer: NSObject, MTKViewDelegate {
    init(device: MTLDevice, scene: Scene) // initWithDevice
}
