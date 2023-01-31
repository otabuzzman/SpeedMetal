import SwiftUI

import MetalKit
import MetalFX
import simd

class RendererControl: ObservableObject {
    static let shared = RendererControl()
    private init() {}

    @Published var drawLoopEnabled = true
    @Published var commandBufferSum: TimeInterval = 0
    @Published var commandBufferAvg: TimeInterval = 0
    @Published var drawFunctionSum: TimeInterval  = 0
    @Published var drawFunctionAvg: TimeInterval  = 0
}

class Renderer: NSObject {
    private(set) var device: MTLDevice

    // options
    var stage: Stage!                { didSet { resetStage() } }
    var framesToRender: UInt32 = 1   { didSet { RendererControl.shared.drawLoopEnabled = true } }
    var usePerPrimitiveData    = true
    var upscaleFactor: Float   = 1.0 { didSet { resetUpscaler() } }

    private var frameWidth: Int    = 0
    private var frameHeight: Int   = 0
    private var raycerWidth: Int   = 0
    private var raycerHeight: Int  = 0
    private var frameCount: UInt32 = 0

    private let maxFramesInFlight = 3
    private var maxFramesSignal: DispatchSemaphore!

    private var queue:   MTLCommandQueue!
    private var library: MTLLibrary!

    private var uniformsBuffer: MTLBuffer!
    private var uniformsBufferOffset = 0
    private var uniformsBufferIndex  = 0
    private let alignedUniformsSize  = (MemoryLayout<Uniforms>.stride + 255) & ~255

    private var resourceBuffer:  MTLBuffer!
    private var resourcesStride: UInt32 = 0

    private var instanceBuffer: MTLBuffer!

    private var raycerTargets: [MTLTexture]!
    private var randomTexture: MTLTexture!

    private var instanceAccelerationStructure:   MTLAccelerationStructure!
    private var primitiveAccelerationStructures: NSMutableArray!

    private var raycerPipeline: MTLComputePipelineState!
    private var shaderPipeline: MTLRenderPipelineState!

    private var intersectionFunctionTable: MTLIntersectionFunctionTable!
    private var useIntersectionFunctions = false

    private var spatialUpscaler: MTLFXSpatialScaler!
    private var upscaledTarget:  MTLTexture!

    private var commandBufferSum: TimeInterval = 0
    private var drawFunctionSum: TimeInterval  = 0

    init(stage: Stage, device: MTLDevice) {
        self.stage  = stage
        self.device = device
        super.init()

        maxFramesSignal = DispatchSemaphore(value: maxFramesInFlight)

        queue = device.makeCommandQueue()!

        let options = MTLCompileOptions()
        library     = try! device.makeLibrary(source: shadersMetal, options: options)

        createBuffers()
        createAccelerationStructures()
        createRaycerAndShaderPipelines()
    }

    private func resetStage() {
        frameCount = 0
        RendererControl.shared.drawLoopEnabled  = true
        commandBufferSum = 0
        drawFunctionSum  = 0

        createBuffers()
        createAccelerationStructures()
        createRaycerAndShaderPipelines()

        let zeroes = Array<vector_float4>(repeating: .zero, count: raycerWidth * raycerHeight)

        for target in raycerTargets {
            target.replace(
                region: MTLRegionMake2D(0, 0, raycerWidth, raycerHeight),
                mipmapLevel: 0,
                withBytes: zeroes,
                bytesPerRow: MemoryLayout<vector_float4>.size * raycerWidth)
        }

    }

    private func resetUpscaler() {
        frameCount = 0
        RendererControl.shared.drawLoopEnabled  = true
        commandBufferSum = 0
        drawFunctionSum  = 0

        createTexturesAndUpscaler()
    }

    private func updateUniforms() {
        uniformsBufferOffset = alignedUniformsSize * uniformsBufferIndex
        uniformsBufferIndex  = (uniformsBufferIndex + 1) % maxFramesInFlight

        let uniforms = uniformsBuffer.contents()
            .advanced(by: uniformsBufferOffset)
            .bindMemory(to: Uniforms.self, capacity: 1)

        uniforms.pointee.width  = UInt32(raycerWidth)
        uniforms.pointee.height = UInt32(raycerHeight)

        uniforms.pointee.frameCount  = frameCount
        frameCount                  += 1

        uniforms.pointee.lightCount  = stage.lightCount

        let fieldOfView: Float = 45.0 * (Float.pi / 180.0 )
        let aspectRatio        = Float(raycerWidth) / Float(raycerHeight)
        let imagePlaneHeight   = tanf(fieldOfView / 2.0)
        let imagePlaneWidth    = aspectRatio * imagePlaneHeight

        let position = stage.viewerStandingAtLocation
        let forward  = simd_normalize(stage.viewerLookingAtLocation - position)
        let right    = simd_normalize(simd_cross(forward, stage.viewerHeadingUpDirection))
        let up       = simd_normalize(simd_cross(right, forward))

        uniforms.pointee.camera.position = position
        uniforms.pointee.camera.forward  = forward
        uniforms.pointee.camera.right    = right * imagePlaneWidth
        uniforms.pointee.camera.up       = up * imagePlaneHeight
    }

    private func createBuffers() {
        let uniformsBufferSize = alignedUniformsSize * maxFramesInFlight
        uniformsBuffer = device.makeBuffer(
            length: uniformsBufferSize,
            options: [.storageModeShared])

        uniformsBufferOffset = 0
        uniformsBufferIndex  = 0

        stage.createBuffers()

        resourcesStride = 0
        for geometry in stage.geometries {
            let geometry = geometry as! Geometry

            if geometry.resources().count * MemoryLayout<UInt64>.size > resourcesStride {
                resourcesStride = UInt32(geometry.resources().count * MemoryLayout<UInt64>.size)
            }
        }

        resourceBuffer = device.makeBuffer(
            length: Int(resourcesStride) * stage.geometries.count,
            options: [.storageModeShared])

        for geometryIndex in 0..<stage.geometries.count {
            let geometry = stage.geometries[geometryIndex] as! Geometry

            let resources       = geometry.resources()
            let resourceHandles = resourceBuffer.contents().advanced(by: geometryIndex * Int(resourcesStride))

            for resourceIndex in 0..<resources.count {
                let resource = resources[resourceIndex]

                if resource.conforms(to: MTLBuffer.self) {
                    resourceHandles.storeBytes(
                        of: (resource as! MTLBuffer).gpuAddress,
                        toByteOffset: resourceIndex * MemoryLayout<UInt64>.size, as: UInt64.self)
                    continue
                }
                if resource.conforms(to: MTLTexture.self) {
                    resourceHandles.storeBytes(
                        of: (resource as! MTLTexture).gpuResourceID,
                        toByteOffset: resourceIndex * MemoryLayout<MTLResourceID>.size, as: MTLResourceID.self)
                }
            }
        }
    }

    private func createAccelerationStructures() {
        primitiveAccelerationStructures = []

        for geometryIndex in 0..<stage.geometries.count {
            let geometry = stage.geometries[geometryIndex] as! Geometry

            let geometryDescriptor = geometry.descriptor()
            geometryDescriptor.intersectionFunctionTableOffset = geometryIndex

            let descriptor = MTLPrimitiveAccelerationStructureDescriptor()
            descriptor.geometryDescriptors = [geometryDescriptor]

            let accelerationStructure = makeAccelerationStructure(descriptor: descriptor)
            primitiveAccelerationStructures.add(accelerationStructure)
        }

        instanceBuffer = device.makeBuffer(
            length: MemoryLayout<MTLAccelerationStructureInstanceDescriptor>.stride * stage.instances.count,
            options: [.storageModeShared])

        let instanceDescriptors = instanceBuffer.contents().bindMemory(to: MTLAccelerationStructureInstanceDescriptor.self, capacity: stage.instances.count)
        for instanceIndex in 0..<stage.instances.count {
            let instance = stage.instances[instanceIndex]

            let geometryIndex = stage.geometries.index(of: instance.geometry)

            instanceDescriptors[instanceIndex].accelerationStructureIndex      = UInt32(geometryIndex)
            instanceDescriptors[instanceIndex].options = instance.geometry.intersectionFunctionName.isEmpty ? .opaque : .nonOpaque
            instanceDescriptors[instanceIndex].intersectionFunctionTableOffset = 0
            instanceDescriptors[instanceIndex].mask                            = UInt32(instance.mask)
            instanceDescriptors[instanceIndex].transformationMatrix            = MTLPackedFloat4x3(instance.transform.transpose)
        }

        let descriptor = MTLInstanceAccelerationStructureDescriptor()
        descriptor.instancedAccelerationStructures = primitiveAccelerationStructures as? [any MTLAccelerationStructure]
        descriptor.instanceCount                   = stage.instances.count
        descriptor.instanceDescriptorBuffer        = instanceBuffer

        instanceAccelerationStructure = makeAccelerationStructure(descriptor: descriptor)
    }

    private func createRaycerAndShaderPipelines() {
        for geometry in stage.geometries {
            if !(geometry as! Geometry).intersectionFunctionName.isEmpty {
                useIntersectionFunctions = true
                break
            }
        }

        var intersectionFunctions: [String: MTLFunction] = [:]

        for geometry in stage.geometries {
            let geometry = geometry as! Geometry
            if geometry.intersectionFunctionName.isEmpty {
                continue
            }
            if let _ = intersectionFunctions.index(forKey: geometry.intersectionFunctionName) {
                continue
            }
            let intersectionFunction = makeSpecializedFunction(withName: geometry.intersectionFunctionName)
            intersectionFunctions[geometry.intersectionFunctionName] = intersectionFunction
        }

        let raycerFunction = makeSpecializedFunction(withName: "raycerKernel")

        raycerPipeline = makeRaycerPipelineState(withFunction: raycerFunction, intersectionFunctions: Array<MTLFunction>(intersectionFunctions.values))

        if useIntersectionFunctions {
            let intersectionFunctionTableDescriptor = MTLIntersectionFunctionTableDescriptor()
            intersectionFunctionTableDescriptor.functionCount = stage.geometries.count

            intersectionFunctionTable = raycerPipeline.makeIntersectionFunctionTable(
                descriptor: intersectionFunctionTableDescriptor)

            if !usePerPrimitiveData {
                intersectionFunctionTable.setBuffer(resourceBuffer, offset: 0, index: 0)
            }

            for geometryIndex in 0..<stage.geometries.count {
                let geometry = stage.geometries[geometryIndex] as! Geometry

                if !geometry.intersectionFunctionName.isEmpty {
                    let intersectionFunction = intersectionFunctions[geometry.intersectionFunctionName]
                    let handle = raycerPipeline.functionHandle(function: intersectionFunction!)
                    intersectionFunctionTable.setFunction(handle, index: geometryIndex)
                }
            }
        }

        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.vertexFunction   = library.makeFunction(name: "copyVertex")
        descriptor.fragmentFunction = library.makeFunction(name: "copyFragment")
        descriptor.colorAttachments[0].pixelFormat = .rgba16Float

        let binaryArchiveDescriptor = MTLBinaryArchiveDescriptor()
        let binaryArchive = try! device.makeBinaryArchive(descriptor: binaryArchiveDescriptor)
        try! binaryArchive.addRenderPipelineFunctions(descriptor: descriptor)
        // try! binaryArchive.serialize(to: URL(string: "shader.metallib")!)

        shaderPipeline = try! device.makeRenderPipelineState(descriptor: descriptor)
    }

    private func makeRaycerPipelineState(withFunction raycerFunction: MTLFunction, intersectionFunctions: [MTLFunction]) -> MTLComputePipelineState {
        var linkedFunctions: MTLLinkedFunctions?
        var pipeline:        MTLComputePipelineState

        if !intersectionFunctions.isEmpty {
            linkedFunctions = MTLLinkedFunctions()
            linkedFunctions!.functions = intersectionFunctions
        }

        let descriptor = MTLComputePipelineDescriptor()
        descriptor.computeFunction                                 = raycerFunction
        descriptor.linkedFunctions                                 = linkedFunctions
        descriptor.threadGroupSizeIsMultipleOfThreadExecutionWidth = true

        let binaryArchiveDescriptor = MTLBinaryArchiveDescriptor()
        let binaryArchive = try! device.makeBinaryArchive(descriptor: binaryArchiveDescriptor)
        try! binaryArchive.addComputePipelineFunctions(descriptor: descriptor)
        // try! binaryArchive.serialize(to: URL(string: "raycer.metallib")!)

        let options = MTLPipelineOption()
        pipeline = try! device.makeComputePipelineState(descriptor: descriptor, options: options, reflection: nil)

        return pipeline
    }

    private func makeSpecializedFunction(withName name: String) -> MTLFunction {
        let constants       = MTLFunctionConstantValues()
        var resourcesStride = self.resourcesStride
        var function: MTLFunction

        constants.setConstantValue(&resourcesStride,          type: .uint, index: 0)
        constants.setConstantValue(&useIntersectionFunctions, type: .bool, index: 1)
        constants.setConstantValue(&usePerPrimitiveData,      type: .bool, index: 2)

        function = try! library.makeFunction(name: name, constantValues: constants)

        return function
    }

    private func makeAccelerationStructure(descriptor: MTLAccelerationStructureDescriptor) -> MTLAccelerationStructure {
        let sizes                 = device.accelerationStructureSizes(descriptor: descriptor)
        let accelerationStructure = device.makeAccelerationStructure(size: sizes.accelerationStructureSize)!

        let scratchBuffer         = device.makeBuffer(
            length: sizes.buildScratchBufferSize,
            options: .storageModePrivate)
        let compactedSizeBuffer   = device.makeBuffer(
            length: MemoryLayout<UInt32>.stride,
            options: .storageModeShared)!

        var commandBuffer         = queue.makeCommandBuffer()!
        var commandEncoder        = commandBuffer.makeAccelerationStructureCommandEncoder()!

        commandEncoder.build(
            accelerationStructure: accelerationStructure,
            descriptor: descriptor,
            scratchBuffer: scratchBuffer!,
            scratchBufferOffset: 0)
        commandEncoder.writeCompactedSize(
            accelerationStructure: accelerationStructure,
            buffer: compactedSizeBuffer,
            offset: 0)

        commandEncoder.endEncoding()
        commandBuffer.commit()

        commandBuffer.waitUntilCompleted()

        let compactedSize                  = compactedSizeBuffer.contents().load(as: UInt32.self)
        let compactedAccelerationStructure = device.makeAccelerationStructure(size: Int(compactedSize))!

        commandBuffer  = queue.makeCommandBuffer()!
        commandEncoder = commandBuffer.makeAccelerationStructureCommandEncoder()!
        commandEncoder.copyAndCompact(
            sourceAccelerationStructure: accelerationStructure,
            destinationAccelerationStructure: compactedAccelerationStructure)

        commandEncoder.endEncoding()
        commandBuffer.commit()

        return compactedAccelerationStructure
    }

    private func createTexturesAndUpscaler() {
        if upscaleFactor > 1.0 {
            raycerWidth  = Int(Float(frameWidth) / upscaleFactor)
            raycerHeight = Int(Float(frameHeight) / upscaleFactor)
        } else {
            raycerWidth  = frameWidth
            raycerHeight = frameHeight
        }

        let textureDescriptor         = MTLTextureDescriptor()
        textureDescriptor.pixelFormat = .rgba32Float
        textureDescriptor.textureType = .type2D
        textureDescriptor.width       = raycerWidth
        textureDescriptor.height      = raycerHeight
        textureDescriptor.storageMode = .shared
        textureDescriptor.usage       = [.shaderRead, .shaderWrite]

        raycerTargets = [
            device.makeTexture(descriptor: textureDescriptor)!,
            device.makeTexture(descriptor: textureDescriptor)!
        ]

        var randomValues = [UInt32](repeating: 0, count: raycerWidth * raycerHeight)

        for i in 0..<raycerWidth * raycerHeight {
            randomValues[i] = .random(in: 0..<(1024 * 1024))
        }

        textureDescriptor.pixelFormat = .r32Uint
        textureDescriptor.usage       = .shaderRead

        randomTexture = device.makeTexture(descriptor: textureDescriptor)!
        randomTexture.replace(
            region: MTLRegionMake2D(0, 0, raycerWidth, raycerHeight),
            mipmapLevel: 0,
            withBytes: &randomValues,
            bytesPerRow: MemoryLayout<UInt32>.size * raycerWidth)

        if upscaleFactor > 1.0 {
            textureDescriptor.pixelFormat = .rgba32Float
            textureDescriptor.width       = frameWidth
            textureDescriptor.height      = frameHeight
            textureDescriptor.usage       = [.shaderRead, .shaderWrite]

            upscaledTarget = device.makeTexture(descriptor: textureDescriptor)!

            let upscalerDescriptor = MTLFXSpatialScalerDescriptor()
            upscalerDescriptor.inputWidth          = raycerWidth
            upscalerDescriptor.inputHeight         = raycerHeight
            upscalerDescriptor.outputWidth         = frameWidth
            upscalerDescriptor.outputHeight        = frameHeight
            upscalerDescriptor.colorTextureFormat  = .rgba32Float
            upscalerDescriptor.outputTextureFormat = .rgba32Float
            upscalerDescriptor.colorProcessingMode = .perceptual

            spatialUpscaler = upscalerDescriptor.makeSpatialScaler(device: device)
        } else {
            upscaledTarget  = nil
            spatialUpscaler = nil
        }
    }
}

extension Renderer: MTKViewDelegate {
    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
        frameWidth  = Int(size.width)
        frameHeight = Int(size.height)

        createTexturesAndUpscaler()
    }

    func draw(in view: MTKView) {
        if !RendererControl.shared.drawLoopEnabled {
            return
        }
        maxFramesSignal.wait()

        let t0 = CFAbsoluteTimeGetCurrent()
        updateUniforms()

        let threadsPerThreadgroup = MTLSizeMake(8, 8, 1)
        let threadgroups          = MTLSizeMake(
            (raycerWidth  + threadsPerThreadgroup.width  - 1) / threadsPerThreadgroup.width,
            (raycerHeight + threadsPerThreadgroup.height - 1) / threadsPerThreadgroup.height, 1)

        let commandBuffer = queue.makeCommandBuffer()!
        commandBuffer.addCompletedHandler() { [self] _ in
            maxFramesSignal.signal()
            commandBufferSum += commandBuffer.gpuEndTime - commandBuffer.gpuStartTime
        }

        let computeEncoder = commandBuffer.makeComputeCommandEncoder()!

        computeEncoder.setBuffer(uniformsBuffer, offset: uniformsBufferOffset, index: 0)
        if !usePerPrimitiveData {
            computeEncoder.setBuffer(resourceBuffer, offset: 0, index: 1)
        }
        computeEncoder.setBuffer(instanceBuffer, offset: 0, index: 2)
        computeEncoder.setBuffer(stage.lightBuffer, offset: 0, index: 3)

        computeEncoder.setAccelerationStructure(instanceAccelerationStructure, bufferIndex: 4)
        computeEncoder.setIntersectionFunctionTable(intersectionFunctionTable, bufferIndex: 5)

        computeEncoder.setTexture(randomTexture, index: 0)
        computeEncoder.setTexture(raycerTargets[0], index: 1)
        computeEncoder.setTexture(raycerTargets[1], index: 2)

        for geometry in stage.geometries {
            for resource in (geometry as! Geometry).resources() {
                computeEncoder.useResource(resource, usage: .read)
            }
        }

        for primitiveAccelerationStructure in primitiveAccelerationStructures {
            computeEncoder.useResource(primitiveAccelerationStructure as! MTLResource, usage: .read)
        }

        computeEncoder.setComputePipelineState(raycerPipeline)

        computeEncoder.dispatchThreadgroups(threadgroups, threadsPerThreadgroup: threadsPerThreadgroup)
        computeEncoder.endEncoding()

        raycerTargets.swapAt(0, 1)

        if upscaleFactor > 1.0 {
            spatialUpscaler.colorTexture  = raycerTargets[0]
            spatialUpscaler.outputTexture = upscaledTarget
            spatialUpscaler.encode(commandBuffer: commandBuffer)

            let blitEncoder = commandBuffer.makeBlitCommandEncoder()!
            blitEncoder.copy(
                from: raycerTargets[0],
                sourceSlice: 0, sourceLevel: 0,
                sourceOrigin: MTLOriginMake(0, 0, 0),
                sourceSize: .init(
                    width: raycerTargets[0].width,
                    height: raycerTargets[0].height, depth: 1),
                to: upscaledTarget,
                destinationSlice: 0, destinationLevel: 0,
                destinationOrigin: MTLOriginMake(0, 0, 0))
            blitEncoder.endEncoding()
        }

        if let currentDrawable = view.currentDrawable {
            let renderPassDescriptor = MTLRenderPassDescriptor()
            renderPassDescriptor.colorAttachments[0].texture    = currentDrawable.texture
            renderPassDescriptor.colorAttachments[0].loadAction = .clear
            renderPassDescriptor.colorAttachments[0].clearColor = MTLClearColorMake(0.0, 0.0, 0.0, 1.0)

            let renderEncoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPassDescriptor)!
            renderEncoder.setRenderPipelineState(shaderPipeline)
            if upscaleFactor > 1.0 {
                renderEncoder.setFragmentTexture(upscaledTarget, index: 0)
            } else {
                renderEncoder.setFragmentTexture(raycerTargets[0], index: 0)
            }
            renderEncoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 6)

            renderEncoder.endEncoding()

            commandBuffer.present(currentDrawable)
        }

        commandBuffer.commit()

        drawFunctionSum += CFAbsoluteTimeGetCurrent() - t0

        if frameCount > framesToRender {
            view.isPaused = true

            RendererControl.shared.drawLoopEnabled  = false
            RendererControl.shared.commandBufferSum = commandBufferSum
            RendererControl.shared.commandBufferAvg = commandBufferSum / Double(frameCount)
            RendererControl.shared.drawFunctionSum  = drawFunctionSum
            RendererControl.shared.drawFunctionAvg  = drawFunctionSum / Double(frameCount)
        }
    }
}

// https://developer.apple.com/forums/thread/653267
extension MTLPackedFloat4x3 {
    init(_ matrix: matrix_float4x4) {
        self.init(columns: (
            MTLPackedFloat3(matrix[0]),
            MTLPackedFloat3(matrix[1]),
            MTLPackedFloat3(matrix[2]),
            MTLPackedFloat3(matrix[3])
        ))
    }
}

extension MTLPackedFloat3 {
    init(_ vector: vector_float4) {
        self.init()
        self.elements = (vector[0], vector[1], vector[2])
    }
}
