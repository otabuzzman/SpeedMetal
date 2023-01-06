import SwiftUI

import MetalKit
import MetalFX
import simd

class RendererControl: ObservableObject {
    @Published var lineUp = LineUp.threeByThree
}

class Renderer: NSObject {
    private var device: MTLDevice
    private var stage:  Stage

    private var frameSize: CGSize      = .zero
    private var frameCount: UInt32     = 1
    private var framesToRender: UInt32 = 100

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
    private var usePerPrimitiveData      = true // Metal 3
    private var useSpatialUpscaler       = false

    private var spatialUpscaler: MTLFXSpatialScaler!
    private var upscaledTarget:  MTLTexture!
    private var upscaleFactor = 2.0

    init(device: MTLDevice, stage: Stage) {
        self.device = device
        self.stage = stage
        super.init()

        maxFramesSignal = DispatchSemaphore(value: maxFramesInFlight)

        library = try! device.makeLibrary(source: shadersMetal, options: MTLCompileOptions())
        queue   = device.makeCommandQueue()!

        reset(stage: stage)
    }

    func reset(stage: Stage) -> Void {
        self.stage = stage

        createBuffers()
        createAccelerationStructures()
        createPipelines()

        frameCount = 1

        guard
            let accumulationTargets = accumulationTargets
        else { return }

        let zeroes = Array<vector_float4>(repeating: .zero, count: Int(frameSize.width * frameSize.height))

        for accumulationTarget in accumulationTargets {
            accumulationTarget.replace(
                region: MTLRegionMake2D(0, 0, Int(frameSize.width), Int(frameSize.height)),
                mipmapLevel: 0,
                withBytes: zeroes,
                bytesPerRow: MemoryLayout<vector_float4>.size * Int(frameSize.width))
        }
    }

    private func updateUniforms() -> Void {
        uniformsBufferOffset = alignedUniformsSize * uniformsBufferIndex

        let uniforms = uniformsBuffer.contents()
            .advanced(by: uniformsBufferOffset)
            .bindMemory(to: Uniforms.self, capacity: 1)

        let position = stage.viewerStandingAtLocation
        let forward  = simd_normalize(stage.viewerLookingAtLocation - position)
        let right    = simd_normalize(simd_cross(forward, stage.viewerHeadingUpDirection))
        let up       = simd_normalize(simd_cross(right, forward))

        uniforms.pointee.camera.position = position
        uniforms.pointee.camera.forward  = forward
        uniforms.pointee.camera.right    = right
        uniforms.pointee.camera.up       = up

        let fieldOfView: Float = 45.0 * (Float.pi / 180.0 )
        let aspectRatio        = Float(frameSize.width) / Float(frameSize.height)
        let imagePlaneHeight   = tanf(fieldOfView / 2.0)
        let imagePlaneWidth    = aspectRatio * imagePlaneHeight

        uniforms.pointee.camera.right *= imagePlaneWidth
        uniforms.pointee.camera.up    *= imagePlaneHeight

        uniforms.pointee.width         = UInt32(frameSize.width)
        uniforms.pointee.height        = UInt32(frameSize.height)

        uniforms.pointee.frameCount    = frameCount
        frameCount                    += 1

        uniforms.pointee.lightCount    = stage.lightCount

        uniformsBufferIndex = (uniformsBufferIndex + 1) % maxFramesInFlight
    }

    private func createBuffers() -> Void {
        let uniformsBufferSize = alignedUniformsSize * maxFramesInFlight
        uniformsBuffer = device.makeBuffer(
            length: uniformsBufferSize,
            options: [.storageModeShared])

        stage.uploadToBuffers()

        resourcesStride = 0

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

            let accelerationStructure = makeAccelerationStructure(accelDescriptor)
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

    private func createPipelines() -> Void {
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

        let raytracingFunction = makeSpecializedFunction(withName: "raytracingKernel")

        raycerPipeline = makeComputePipelineState(withFunction: raytracingFunction, linkedFunctions: Array<MTLFunction>(intersectionFunctions.values))

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

        let renderDescriptor = MTLRenderPipelineDescriptor()
        renderDescriptor.vertexFunction   = library.makeFunction(name: "copyVertex")
        renderDescriptor.fragmentFunction = library.makeFunction(name: "copyFragment")
        renderDescriptor.colorAttachments[0].pixelFormat = .rgba16Float

        let renderBinaryArchiveDescriptor = MTLBinaryArchiveDescriptor()
        do {
            let renderBinaryArchive = try device.makeBinaryArchive(descriptor: renderBinaryArchiveDescriptor)
            try renderBinaryArchive.addRenderPipelineFunctions(descriptor: renderDescriptor)
            // try renderBinaryArchive.serialize(to: URL(string: "shader.metallib")!)
        } catch {
            fatalError(String(format: "harvest shader binary archive failed: \(error)"))
        }

        do {
            shaderPipeline = try device.makeRenderPipelineState(descriptor: renderDescriptor)
        } catch {
            fatalError(String(format: "makeRenderPipelineState failed: \(error)"))
        }
    }

    private func makeComputePipelineState(withFunction function: MTLFunction, linkedFunctions: [MTLFunction]) -> MTLComputePipelineState {
        var mtlLinkedFunctions: MTLLinkedFunctions?
        var pipeline:           MTLComputePipelineState

        if !linkedFunctions.isEmpty {
            mtlLinkedFunctions = MTLLinkedFunctions()
            mtlLinkedFunctions!.functions = linkedFunctions
        }

        let computeDescriptor = MTLComputePipelineDescriptor()
        computeDescriptor.computeFunction                                 = function
        computeDescriptor.linkedFunctions                                 = mtlLinkedFunctions
        computeDescriptor.threadGroupSizeIsMultipleOfThreadExecutionWidth = true

        let computeBinaryArchiveDescriptor = MTLBinaryArchiveDescriptor()
        do {
            let computeBinaryArchive = try device.makeBinaryArchive(descriptor: computeBinaryArchiveDescriptor)
            try computeBinaryArchive.addComputePipelineFunctions(descriptor: computeDescriptor)
            // try computeBinaryArchive.serialize(to: URL(string: "raycer.metallib")!)
        } catch {
            fatalError(String(format: "harvest compute binary archive failed: \(error)"))
        }

        do {
            pipeline = try device.makeComputePipelineState(
                descriptor: computeDescriptor, options: MTLPipelineOption(), reflection: nil)
        } catch {
            fatalError(String(format: "makeComputePipelineState failed: \(error)"))
        }

        return pipeline
    }

    private func makeSpecializedFunction(withName name: String) -> MTLFunction {
        let constants       = MTLFunctionConstantValues()
        var resourcesStride = self.resourcesStride
        var function: MTLFunction

        constants.setConstantValue(&resourcesStride,          type: .uint, index: 0)
        constants.setConstantValue(&useIntersectionFunctions, type: .bool, index: 1)
        constants.setConstantValue(&usePerPrimitiveData,      type: .bool, index: 2)

        do {
            function = try library.makeFunction(name: name, constantValues: constants)
        } catch {
            fatalError(String(format: "makeFunction failed: \(error)"))
        }

        return function
    }

    private func makeAccelerationStructure(descriptor: MTLAccelerationStructureDescriptor) -> MTLAccelerationStructure {
        let accelSizes            = device.accelerationStructureSizes(descriptor: descriptor)
        let accelerationStructure = device.makeAccelerationStructure(
            size: accelSizes.accelerationStructureSize)!

        let scratchBuffer         = device.makeBuffer(
            length: accelSizes.buildScratchBufferSize,
            options: .storageModePrivate)

        var commandBuffer         = queue.makeCommandBuffer()!
        var commandEncoder        = commandBuffer.makeAccelerationStructureCommandEncoder()!

        let compactedSizeBuffer   = device.makeBuffer(
            length: MemoryLayout<UInt32>.stride,
            options: .storageModeShared)!

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
        let upscalerDescriptor = MTLFXSpatialScalerDescriptor()
        upscalerDescriptor.inputWidth   = Int(frameSize.width)
        upscalerDescriptor.inputHeight  = Int(frameSize.height)
        upscalerDescriptor.outputWidth  = Int(frameSize.width * upscaleFactor)
        upscalerDescriptor.outputHeight = Int(frameSize.height * upscaleFactor)
        upscalerDescriptor.colorTextureFormat  = .rgba32Float
        upscalerDescriptor.outputTextureFormat = .rgba32Float
        upscalerDescriptor.colorProcessingMode = .perceptual

        spatialUpscaler = upscalerDescriptor.makeSpatialScaler(device: device)
    }
}

extension Renderer: MTKViewDelegate {
    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) -> Void {
        frameSize.width  = size.width / upscaleFactor
        frameSize.height = size.height / upscaleFactor

        let textureDescriptor         = MTLTextureDescriptor()
        textureDescriptor.pixelFormat = .rgba32Float
        textureDescriptor.textureType = .type2D
        textureDescriptor.width       = Int(frameSize.width)
        textureDescriptor.height      = Int(frameSize.height)
        textureDescriptor.storageMode = .shared
        textureDescriptor.usage       = [.shaderRead, .shaderWrite]

        accumulationTargets = [
            device.makeTexture(descriptor: textureDescriptor)!,
            device.makeTexture(descriptor: textureDescriptor)!
        ]

        if useSpatialUpscaler {
            textureDescriptor.width  = Int(frameSize.width * upscaleFactor)
            textureDescriptor.height = Int(frameSize.height * upscaleFactor)
            upscaledTarget = device.makeTexture(descriptor: textureDescriptor)!

            createSpatialUpscaler()
        }

        var randomValues = [UInt32](repeating: 0, count: Int(frameSize.width * frameSize.height))

        for i in 0..<Int(frameSize.width * frameSize.height) {
            randomValues[i] = UInt32.random(in: 0..<(1024 * 1024))
        }

        textureDescriptor.pixelFormat = .r32Uint
        textureDescriptor.storageMode = .shared
        textureDescriptor.usage       = .shaderRead

        randomTexture = device.makeTexture(descriptor: textureDescriptor)!
        randomTexture.replace(
            region: MTLRegionMake2D(0, 0, Int(frameSize.width), Int(frameSize.height)),
            mipmapLevel: 0,
            withBytes: &randomValues,
            bytesPerRow: MemoryLayout<UInt32>.size * Int(frameSize.width))

        frameCount = 1
    }

    func draw(in view: MTKView) -> Void {
        if frameCount % framesToRender == 0 {
            view.isPaused = true
        }

        maxFramesSignal.wait()

        let commandBuffer = queue.makeCommandBuffer()!
        commandBuffer.addCompletedHandler() { [self] _ in
            maxFramesSignal.signal()
        }

        updateUniforms()

        let width  = Int(frameSize.width)
        let height = Int(frameSize.height)

        let threadsPerThreadgroup = MTLSizeMake(8, 8, 1)
        let threadgroups          = MTLSizeMake(
            (width  + threadsPerThreadgroup.width  - 1) / threadsPerThreadgroup.width,
            (height + threadsPerThreadgroup.height - 1) / threadsPerThreadgroup.height, 1)

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

        if useSpatialUpscaler {
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
            if useSpatialUpscaler {
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
