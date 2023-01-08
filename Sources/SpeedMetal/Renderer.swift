import SwiftUI

import MetalKit
import MetalFX
import simd

class RendererOptions: ObservableObject {
    @Published var lineUp = LineUp.threeByThree
    var framesToRender: UInt32 = 1
    var usePerPrimitiveData    = false
    var upscaleFactor: Float   = 1.0

    var view: MTKView?
}

class Renderer: NSObject {
    private var device:  MTLDevice
    private var stage:   Stage
    private var options: RendererOptions

    private var frameWidth: Int  = 0
    private var frameHeight: Int = 0
    private var frameCount: UInt32 = 1
    
    private let maxFramesInFlight = 3
    private var maxFramesSignal: DispatchSemaphore!

    private var queue:   MTLCommandQueue!
    private var library: MTLLibrary!

    private var uniformsBuffer: MTLBuffer!
    private var uniformsBufferOffset = 0
    private var uniformsBufferIndex  = 0
    private let alignedUniformsSize  = (MemoryLayout<Uniforms>.stride + 255) & ~255

    private var resourceBuffer: MTLBuffer!
    private var resourcesStride: UInt32  = 0

    private var instanceBuffer: MTLBuffer!

    private var accumulationTargets: [MTLTexture]!
    private var randomTexture:       MTLTexture!

    private var instanceAccelerationStructure:   MTLAccelerationStructure!
    private var primitiveAccelerationStructures: NSMutableArray!

    private var raycerPipeline: MTLComputePipelineState!
    private var shaderPipeline: MTLRenderPipelineState!

    private var intersectionFunctionTable: MTLIntersectionFunctionTable!
    private var useIntersectionFunctions = false
    
    private var spatialUpscaler: MTLFXSpatialScaler!
    private var upscaledTarget:  MTLTexture!

    init(device: MTLDevice, stage: Stage, options: RendererOptions) {
        self.device  = device
        self.stage   = stage
        self.options = options
        super.init()

        maxFramesSignal = DispatchSemaphore(value: maxFramesInFlight)

        library = try! device.makeLibrary(source: shadersMetal, options: MTLCompileOptions())
        queue   = device.makeCommandQueue()!

        reset(stage: stage)
    }

    func reset(stage: Stage) -> Void {
        self.stage = stage

        frameCount      = 1
        resourcesStride = 0

        createBuffers()
        createAccelerationStructures()
        createRaycerAndShaderPipelines()

        guard
            let accumulationTargets = accumulationTargets
        else { return }

        let zeroes = Array<vector_float4>(repeating: .zero, count: frameWidth * frameHeight)

        for accumulationTarget in accumulationTargets {
            accumulationTarget.replace(
                region: MTLRegionMake2D(0, 0, frameWidth, frameHeight),
                mipmapLevel: 0,
                withBytes: zeroes,
                bytesPerRow: MemoryLayout<vector_float4>.size * frameWidth)
        }
    }

    private func updateUniforms() -> Void {
        uniformsBufferOffset = alignedUniformsSize * uniformsBufferIndex
        uniformsBufferIndex  = (uniformsBufferIndex + 1) % maxFramesInFlight

        let uniforms = uniformsBuffer.contents()
            .advanced(by: uniformsBufferOffset)
            .bindMemory(to: Uniforms.self, capacity: 1)

        uniforms.pointee.width  = UInt32(frameWidth)
        uniforms.pointee.height = UInt32(frameHeight)

        uniforms.pointee.frameCount  = frameCount
        frameCount                  += 1

        uniforms.pointee.lightCount  = stage.lightCount

        let fieldOfView: Float = 45.0 * (Float.pi / 180.0 )
        let aspectRatio        = Float(frameWidth) / Float(frameHeight)
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

    private func createBuffers() -> Void {
        let uniformsBufferSize = alignedUniformsSize * maxFramesInFlight
        uniformsBuffer = device.makeBuffer(
            length: uniformsBufferSize,
            options: [.storageModeShared])

        stage.uploadToBuffers()

        for geometry in stage.geometries {
            let geometry = geometry as! Geometry

            // Metal 3
            if geometry.resources().count * MemoryLayout<UInt64>.size > resourcesStride {
                resourcesStride = UInt32(geometry.resources().count * MemoryLayout<UInt64>.size)
            }
        }

        resourceBuffer = device.makeBuffer(
            length: Int(resourcesStride) * stage.geometries.count,
            options: [.storageModeShared])

        for geometryIndex in 0..<stage.geometries.count {
            let geometry = stage.geometries[geometryIndex] as! Geometry

            // Metal 3
            let resources       = geometry.resources()
            let resourceHandles = resourceBuffer.contents().advanced(by: geometryIndex * Int(resourcesStride))

            for resourceIndex in 0..<resources.count {
                let resource = resources[resourceIndex]

                if resource.conforms(to: MTLBuffer.self) {
                    resourceHandles.storeBytes(
                        of: (resource as! MTLBuffer).gpuAddress,
                        toByteOffset: resourceIndex * MemoryLayout<UInt64>.size, as: UInt64.self)
                } else {
                    if resource.conforms(to: MTLTexture.self) {
                        resourceHandles.storeBytes(
                            of: (resource as! MTLTexture).gpuResourceID,
                            toByteOffset: resourceIndex * MemoryLayout<MTLResourceID>.size, as: MTLResourceID.self)
                    }
                }
            }
        }
    }

    private func createAccelerationStructures() -> Void {
        primitiveAccelerationStructures = []

        for i in 0..<stage.geometries.count {
            let geometry = stage.geometries[i] as! Geometry

            let geometryDescriptor = geometry.descriptor()
            geometryDescriptor.intersectionFunctionTableOffset = i

            let accelDescriptor = MTLPrimitiveAccelerationStructureDescriptor()
            accelDescriptor.geometryDescriptors = [geometryDescriptor]

            let accelerationStructure = makeAccelerationStructure(descriptor: accelDescriptor)
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
            instanceDescriptors[instanceIndex].options                         = instance.geometry.intersectionFunctionName.isEmpty ? .opaque : .nonOpaque
            instanceDescriptors[instanceIndex].intersectionFunctionTableOffset = 0
            instanceDescriptors[instanceIndex].mask                            = UInt32(instance.mask)
            instanceDescriptors[instanceIndex].transformationMatrix            = MTLPackedFloat4x3(instance.transform.transpose)

        }

        let accelDescriptor = MTLInstanceAccelerationStructureDescriptor()
        accelDescriptor.instancedAccelerationStructures = primitiveAccelerationStructures as? [any MTLAccelerationStructure]
        accelDescriptor.instanceCount                   = stage.instances.count
        accelDescriptor.instanceDescriptorBuffer        = instanceBuffer

        instanceAccelerationStructure = makeAccelerationStructure(descriptor: accelDescriptor)
    }

    private func createRaycerAndShaderPipelines() -> Void {
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

            if !options.usePerPrimitiveData {
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
        do {
            let binaryArchive = try device.makeBinaryArchive(descriptor: binaryArchiveDescriptor)
            try binaryArchive.addRenderPipelineFunctions(descriptor: descriptor)
            // try binaryArchive.serialize(to: URL(string: "shader.metallib")!)
        } catch {
            fatalError(String(format: "harvest shader binary archive failed: \(error)"))
        }

        do {
            shaderPipeline = try device.makeRenderPipelineState(descriptor: descriptor)
        } catch {
            fatalError(String(format: "makeRenderPipelineState failed: \(error)"))
        }
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
        do {
            let binaryArchive = try device.makeBinaryArchive(descriptor: binaryArchiveDescriptor)
            try binaryArchive.addComputePipelineFunctions(descriptor: descriptor)
            // try binaryArchive.serialize(to: URL(string: "raycer.metallib")!)
        } catch {
            fatalError(String(format: "harvest raycer binary archive failed: \(error)"))
        }

        do {
            pipeline = try device.makeComputePipelineState(
                descriptor: descriptor, options: MTLPipelineOption(), reflection: nil)
        } catch {
            fatalError(String(format: "makeComputePipelineState failed: \(error)"))
        }

        return pipeline
    }

    private func makeSpecializedFunction(withName name: String) -> MTLFunction {
        let constants       = MTLFunctionConstantValues()
        var resourcesStride = self.resourcesStride
        var function: MTLFunction

        constants.setConstantValue(&resourcesStride,             type: .uint, index: 0)
        constants.setConstantValue(&useIntersectionFunctions,    type: .bool, index: 1)
        constants.setConstantValue(&options.usePerPrimitiveData, type: .bool, index: 2)

        do {
            function = try library.makeFunction(name: name, constantValues: constants)
        } catch {
            fatalError(String(format: "makeFunction failed: \(error)"))
        }

        return function
    }

    private func makeAccelerationStructure(descriptor: MTLAccelerationStructureDescriptor) -> MTLAccelerationStructure {
        let accelSizes            = device.accelerationStructureSizes(descriptor: descriptor)
        let accelerationStructure = device.makeAccelerationStructure(size: accelSizes.accelerationStructureSize)!

        let scratchBuffer         = device.makeBuffer(
            length: accelSizes.buildScratchBufferSize,
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

    private func createSpatialUpscaler() -> Void {
        let upscaleFactor = options.upscaleFactor
        let descriptor = MTLFXSpatialScalerDescriptor()
        descriptor.inputWidth   = frameWidth
        descriptor.inputHeight  = frameHeight
        descriptor.outputWidth  = Int(Float(frameWidth) * upscaleFactor)
        descriptor.outputHeight = Int(Float(frameHeight) * upscaleFactor)
        descriptor.colorTextureFormat  = .rgba32Float
        descriptor.outputTextureFormat = .rgba32Float
        descriptor.colorProcessingMode = .perceptual

        spatialUpscaler = descriptor.makeSpatialScaler(device: device)
    }
}

extension Renderer: MTKViewDelegate {
    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) -> Void {
        options.view = view
        
        let upscaleFactor = options.upscaleFactor
        frameWidth  = Int(Float(size.width) / upscaleFactor)
        frameHeight = Int(Float(size.height) / upscaleFactor)

        let descriptor         = MTLTextureDescriptor()
        descriptor.pixelFormat = .rgba32Float
        descriptor.textureType = .type2D
        descriptor.width       = frameWidth
        descriptor.height      = frameHeight
        descriptor.storageMode = .shared
        descriptor.usage       = [.shaderRead, .shaderWrite]

        accumulationTargets = [
            device.makeTexture(descriptor: descriptor)!,
            device.makeTexture(descriptor: descriptor)!
        ]

        if options.upscaleFactor > 1.0 {
            descriptor.width  = Int(Float(frameWidth) * upscaleFactor)
            descriptor.height = Int(Float(frameHeight) * upscaleFactor)
            upscaledTarget = device.makeTexture(descriptor: descriptor)!

            createSpatialUpscaler()
        }

        var randomValues = [UInt32](repeating: 0, count: frameWidth * frameHeight)

        for i in 0..<frameWidth * frameHeight {
            randomValues[i] = UInt32.random(in: 0..<(1024 * 1024))
        }

        descriptor.pixelFormat = .r32Uint
        descriptor.storageMode = .shared
        descriptor.usage       = .shaderRead

        randomTexture = device.makeTexture(descriptor: descriptor)!
        randomTexture.replace(
            region: MTLRegionMake2D(0, 0, frameWidth, frameHeight),
            mipmapLevel: 0,
            withBytes: &randomValues,
            bytesPerRow: MemoryLayout<UInt32>.size * frameWidth)

        frameCount = 1
    }

    func draw(in view: MTKView) -> Void {
        if frameCount % options.framesToRender == 0 {
            view.isPaused = true
        }

        maxFramesSignal.wait()

        updateUniforms()

        let threadsPerThreadgroup = MTLSizeMake(8, 8, 1)
        let threadgroups          = MTLSizeMake(
            (frameWidth  + threadsPerThreadgroup.width  - 1) / threadsPerThreadgroup.width,
            (frameHeight + threadsPerThreadgroup.height - 1) / threadsPerThreadgroup.height, 1)

        let commandBuffer = queue.makeCommandBuffer()!
        commandBuffer.addCompletedHandler() { [self] _ in
            maxFramesSignal.signal()
        }

        let computeEncoder = commandBuffer.makeComputeCommandEncoder()!

        computeEncoder.setBuffer(uniformsBuffer, offset: uniformsBufferOffset, index: 0)
        if !options.usePerPrimitiveData {
            computeEncoder.setBuffer(resourceBuffer, offset: 0, index: 1)
        }
        computeEncoder.setBuffer(instanceBuffer, offset: 0, index: 2)
        computeEncoder.setBuffer(stage.lightBuffer, offset: 0, index: 3)

        computeEncoder.setAccelerationStructure(instanceAccelerationStructure, bufferIndex: 4)
        computeEncoder.setIntersectionFunctionTable(intersectionFunctionTable, bufferIndex: 5)

        computeEncoder.setTexture(randomTexture, index: 0)
        computeEncoder.setTexture(accumulationTargets[0], index: 1)
        computeEncoder.setTexture(accumulationTargets[1], index: 2)

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

        accumulationTargets.swapAt(0, 1)

        if options.upscaleFactor > 1.0 {
            spatialUpscaler.colorTexture = accumulationTargets[0]
            spatialUpscaler.outputTexture = upscaledTarget
            spatialUpscaler.encode(commandBuffer: commandBuffer)
        }

        if let currentDrawable = view.currentDrawable {
            let renderPassDescriptor = MTLRenderPassDescriptor()
            renderPassDescriptor.colorAttachments[0].texture    = currentDrawable.texture
            renderPassDescriptor.colorAttachments[0].loadAction = .clear
            renderPassDescriptor.colorAttachments[0].clearColor = MTLClearColorMake(0.0, 0.0, 0.0, 1.0)

            let renderEncoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPassDescriptor)!
            renderEncoder.setRenderPipelineState(shaderPipeline)
            if options.upscaleFactor > 1.0 {
                renderEncoder.setFragmentTexture(upscaledTarget, index: 0)
            } else {
                renderEncoder.setFragmentTexture(accumulationTargets[0], index: 0)
            }
            renderEncoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 6)

            renderEncoder.endEncoding()

            commandBuffer.present(currentDrawable)
        }

        commandBuffer.commit()
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
