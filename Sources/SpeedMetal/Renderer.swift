import MetalKit
import simd

protocol Renderer: NSObject, MTKViewDelegate {
    init(device: MTLDevice, stage: Stage) // initWithDevice
}
