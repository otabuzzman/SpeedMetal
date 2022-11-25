import MetalKit
import simd

static let maxFramesInFlight         = 3
static let alignedUniformsSize: UInt = (sizeof(Uniforms) + 255) & ~255

protocol Renderer: MTKViewDelegate {
    var device:  MTLDevice?

    var queue:   MTLCommandQueue
    var library: MTLLibrary

    var uniformBuffer: MTLBuffer?

    var instanceAccelerationStructure:   MTLAccelerationStructure
    var primitiveAccelerationStructures: NSMutableArray

    var raytracingPipeline:        MTLComputePipelineState
    var copyPipeline:              MTLRenderPipelineState

    var accumulationTargets:       MTLTexture
    var randomTexture:             MTLTexture

    var resourceBuffer:            MTLBuffer
    var instanceBuffer:            MTLBuffer

    var intersectionFunctionTable: MTLIntersectionFunctionTable

    var sem:  DispatchSemaphore
    var size: CGSize             = .zero
    var uniformBufferOffset      = 0
    var uniformBufferIndex       = 0

    var frameIndex: UInt         = 0

    var stage: Stage

    var resourcesStride: UInt    = 0
    var useIntersectionFunctions = false
    var usePerPrimitiveData      = false

    init(device: MTLDevice, stage: Stage) { // initWithDevice
        self.device = device

        sem = DispatchSemaphore(value: maxFramesInFlight)

        self.stage = stage

        loadMetal()
        createBuffers()
        createAccelerationStructures()
        createPipelines()
    }

    func mtkView(view: MTKView, drawableSizeWillChange size: CGSize) -> Void {
        self.size = size

        let textureDescriptor         = MTLTextureDescriptor()
        textureDescriptor.pixelFormat = MTLPixelFormatRGBA32Float
        textureDescriptor.textureType = MTLTextureType2D
        textureDescriptor.width       = size.width
        textureDescriptor.height      = size.height
        textureDescriptor.storageMode = MTLStorageModePrivate;
        textureDescriptor.usage       = MTLTextureUsageShaderRead | MTLTextureUsageShaderWrite

        for i in 0..<2 {
            accumulationTargets[i] = device.newTextureWithDescriptor(textureDescriptor)
        }

        textureDescriptor.pixelFormat = MTLPixelFormatR32Uint
        textureDescriptor.usage       = MTLTextureUsageShaderRead
        textureDescriptor.storageMode = MTLResourceOptions.storageModeShared

        randomTexture = device.newTextureWithDescriptor(textureDescriptor)

        var randomValues = [UInt32](repeating: 0, count: size.width * size.height)

        for i in 0..<size.width * size.height {
            randomValues[i] = UInt32.random(0..<(1024 * 1024))
        }

        randomTexture.replaceRegion(MTLRegionMake2D(0, 0, size.width, size.height), mipmapLevel: 0, withBytes: randomValues, bytesPerRow: sizeof(UInt32) * size.width)

        frameIndex = 0
    }

    private func updateUniforms() -> Void {
        uniformBufferOffset = alignedUniformsSize * uniformBufferIndex

        let uniforms = uniformBuffer.contents + uniformBufferOffset

        let position = stage.cameraPosition
        let target   = stage.cameraTarget
        var up       = stage.cameraUp

        let forward  = vector_normalize(target - position)
        let right    = vector_normalize(vector_cross(forward, up))
        up           = vector_normalize(vector_cross(right, forward))

        uniforms.camera.position = position
        uniforms.camera.forward  = forward
        uniforms.camera.right    = right
        uniforms.camera.up       = up

        let fieldOfView          = 45.0 * (Float.pi / 180.0)
        let aspectRatio          = Float(size.width) / Float(size.height)
        let imagePlaneHeight     = tanf(fieldOfView / 2.0)
        let imagePlaneWidth      = aspectRatio * imagePlaneHeight

        uniforms.camera.right   *= imagePlaneWidth
        uniforms.camera.up      *= imagePlaneHeight

        uniforms.width           = UInt(size.width)
        uniforms.height          = UInt(size.height)

        uniforms.frameIndex      = frameIndex + 1

        uniforms.lightCount      = UInt(stage.lightCount)

        uniformBufferIndex       = (uniformBufferIndex + 1) % maxFramesInFlight
    }

    func draw(view: MTKView) -> Void { // drawInMTKView
        sem.wait()

        let commandBuffer = queue.commandBuffer()
        commandBuffer.addCompletedHandler() { _ in
            sem.signal()
        }

        updateUniforms()

        let width  = UInt(size.width)
        let height = UInt(size.height)

        let threadsPerThreadgroup = MTLSizeMake(8, 8, 1)
        let threadgroups          = MTLSizeMake((width  + threadsPerThreadgroup.width  - 1) / threadsPerThreadgroup.width, (height + threadsPerThreadgroup.height - 1) / threadsPerThreadgroup.height, 1)

        let computeEncoder = commandBuffer.computeCommandEncoder()

        computeEncoder.setBuffer(uniformBuffer, offset: uniformBufferOffset, atIndex: 0)
        if (!usePerPrimitiveData) {
            computeEncoder.setBuffer(resourceBuffer, offset: 0, atIndex: 1)
        }
        computeEncoder.setBuffer(instanceBuffer, offset: 0, atIndex: 2)
        computeEncoder.setBuffer(scene.lightBuffer, offset: 0, atIndex: 3)

        computeEncoder.setAccelerationStructure(instanceAccelerationStructure, atBufferIndex: 4)
        computeEncoder.setIntersectionFunctionTable(intersectionFunctionTable, atBufferIndex: 5)

        computeEncoder.setTexture(randomTexture, atIndex: 0)
        computeEncoder.setTexture(accumulationTargets[0], atIndex: 1)
        computeEncoder.setTexture(accumulationTargets[1], atIndex: 2)

        for geometry in stage.geometries {
            for resource in geometry.resources {
                computeEncoder.useResource(resource, usage: MTLResourceUsageRead)
            }
        }

        for primitiveAccelerationStructure in primitiveAccelerationStructures {
            computeEncoder.useResource(primitiveAccelerationStructure, usage: MTLResourceUsageRead)
        }

        computeEncoder.setComputePipelineState(raytracingPipeline)

        computeEncoder.dispatchThreadgroups(threadgroups, threadsPerThreadgroup: threadsPerThreadgroup)
        computeEncoder.endEncoding()

        accumulationTargets.swapAt(0, 1)

        if view.currentDrawable {
            let renderPassDescriptor = MTLRenderPassDescriptor()
            renderPassDescriptor.colorAttachments[0].texture    = view.currentDrawable.texture
            renderPassDescriptor.colorAttachments[0].loadAction = MTLLoadActionClear
            renderPassDescriptor.colorAttachments[0].clearColor = MTLClearColorMake(0.0, 0.0, 0.0, 1.0)

            // Create a render command encoder.
            let renderEncoder = commandBuffer.renderCommandEncoderWithDescriptor(renderPassDescriptor)
            renderEncoder.setRenderPipelineState(copyPipeline)
            renderEncoder.setFragmentTexture(accumulationTargets[0], atIndex: 0)
            renderEncoder.drawPrimitives(MTLPrimitiveTypeTriangle, vertexStart: 0, vertexCount: 6)

            renderEncoder.endEncoding()

            commandBuffer.presentDrawable(view.currentDrawable)
        }

        commandBuffer.commit()
    }

    private func loadMetal() -> Void {
        library = device.newDefaultLibrary()
        queue   = device.newCommandQueue()
    }

    private func createBuffers() -> Void {
        let uniformBufferSize = alignedUniformsSize * maxFramesInFlight
        uniformBuffer = device.newBufferWithLength(uniformBufferSize)

        stage.uploadToBuffers()

        resourcesStride = 0

        for geometry in stage.geometries {
            // Metal 3
            if #available(iOS 16, macOS 13, *) {
                if geometry.resources.count * sizeof(UInt64) > resourcesStride) {
                    resourcesStride = geometry.resources.count * sizeof(UInt64)
                }
            } else {
                let encoder = newArgumentEncoderForResources(geometry.resources)

                if encoder.encodedLength > resourcesStride {
                    resourcesStride = encoder.encodedLength
                }
            }
        }

        resourceBuffer = device.newBufferWithLength(resourcesStride * stage.geometries.count)

        for geometryIndex in 0..<stage.geometries.count {
            let geometry = stage.geometries[geometryIndex]

            // Metal 3
            if #available(iOS 16, macOS 13, *) {
                let resources = geometry.resources()

                let resourceHandles = resourceBuffer.contents + resourcesStride * geometryIndex
                resourceHandles.bindMemory(to: UInt64.self, capacity: resources.count)

                for argumentIndex in 0..<resources.count {
                    let resource = resources[argumentIndex]

                    if resource.conforms(to: MTLBuffer) {
                        resourceHandles.storeBytes(of: resource.gpuAddress, toByteOffset: argumentIndex * sizeof(UInt64), as: UInt64.self)
                    } else {
                        if resource.conforms(to: MTLTexture) {
                            resourceHandles.storeBytes(of: resource.gpuResourceID, toByteOffset: argumentIndex * sizeof(UInt64), as: UInt64.self)
                        }
                    }
                }
            } else {
                let encoder = newArgumentEncoderForResources(geometry.resources)
                encoder.setArgumentBuffer(resourceBuffer, offset: resourcesStride * geometryIndex)

                for argumentIndex in 0..<geometry.resources.count {
                    let resource = geometry.resources[argumentIndex]

                    if resource.conforms(to: MTLBuffer) {
                        encoder.setBuffer(resource, offset: 0 atIndex: argumentIndex)
                    } else {
                        if resource.conforms(to: MTLTexture) {
                            encoder.setTexture(resource, atIndex: argumentIndex)
                        }
                    }
                }
            }
        }
    }

    private func createAccelerationStructures() -> Void {
        let _primitiveAccelerationStructures = [MTLAccelerationStructure]()

        for i = 0..<stage.geometries.count {
            let mesh = stage.geometries[i]

            let geometryDescriptor = mesh.geometryDescriptor()
            geometryDescriptor.intersectionFunctionTableOffset = i

            let accelDescriptor = MTLPrimitiveAccelerationStructureDescriptor()
            accelDescriptor.geometryDescriptors = [geometryDescriptor]

            let accelerationStructure = newAccelerationStructureWithDescriptor(accelDescriptor)
            primitiveAccelerationStructures.addObject(accelerationStructure)
        }

        let instanceBuffer = device.newBufferWithLength(sizeof(MTLAccelerationStructureInstanceDescriptor) * stage.instances.count)

        let instanceDescriptors = instanceBuffer.contents
        for instanceIndex in 0..<stage.instances.count {
            let instance = stage.instances[instanceIndex]

            let geometryIndex = stage.geometries.indexOfObject(instance.geometry)

            instanceDescriptors[instanceIndex].accelerationStructureIndex      = geometryIndex
            instanceDescriptors[instanceIndex].options                         = instance.geometry.intersectionFunctionName == nil ? MTLAccelerationStructureInstanceOptionOpaque : 0
            instanceDescriptors[instanceIndex].intersectionFunctionTableOffset = 0
            instanceDescriptors[instanceIndex].mask                            = instance.mask

            for column in 0..<4 {
                for row in 0..<3 {
                    instanceDescriptors[instanceIndex].transformationMatrix.columns[column][row] = instance.transform.columns[column][row]
                }
            }

        let accelDescriptor = MTLInstanceAccelerationStructureDescriptor()
        accelDescriptor.instancedAccelerationStructures = primitiveAccelerationStructures
        accelDescriptor.instanceCount                   = stage.instances.count
        accelDescriptor.instanceDescriptorBuffer        = instanceBuffer

        instanceAccelerationStructure = newAccelerationStructureWithDescriptor(accelDescriptor)
    }

    private func createPipelines() -> Void {
        var useIntersectionFunctions = false

        // Metal 3
        if #available(iOS 16, macOS 13, *) {
            usePerPrimitiveData = true
        } else {
            usePerPrimitiveData = false
        }

        for geometry in stage.geometries {
            if geometry.intersectionFunctionName {
                useIntersectionFunctions = true

                break
            }
        }

        var intersectionFunctions = [String, MTLFunction]()

        for geometry in stage.geometries {
            if !geometry.intersectionFunctionName || intersectionFunctions[geometry.intersectionFunctionName] {
                continue
            }

            let intersectionFunction = specializedFunctionWithName(geometry.intersectionFunctionName)
            intersectionFunctions[geometry.intersectionFunctionName] = intersectionFunction
        }

        let raytracingFunction = specializedFunctionWithName("raytracingKernel")

        let raytracingPipeline = newComputePipelineStateWithFunction(raytracingFunction, linkedFunctions: intersectionFunctions)

        if useIntersectionFunctions {
            let intersectionFunctionTableDescriptor = MTLIntersectionFunctionTableDescriptor()
            intersectionFunctionTableDescriptor.functionCount = stage.geometries.count

            let intersectionFunctionTable = raytracingPipeline.newIntersectionFunctionTableWithDescriptor(intersectionFunctionTableDescriptor)

            if !_usePerPrimitiveData {
                intersectionFunctionTable.setBuffer(resourceBuffer, offset: 0, atIndex: 0)
            }

            for geometryIndex in 0..<stage.geometries.count {
                let geometry = stage.geometries[geometryIndex]

                if geometry.intersectionFunctionName {
                    let intersectionFunction = intersectionFunctions[geometry.intersectionFunctionName]
                    let handle               = raytracingPipeline.functionHandleWithFunction(intersectionFunction)
                    intersectionFunctionTable.setFunction(handle, atIndex: geometryIndex)
                }
            }
        }

        let renderDescriptor = MTLRenderPipelineDescriptor()
        renderDescriptor.vertexFunction                  = library.newFunctionWithName("copyVertex")
        renderDescriptor.fragmentFunction                = library.newFunctionWithName("copyFragment")
        renderDescriptor.colorAttachments[0].pixelFormat = MTLPixelFormatRGBA16Float

        try {
            copyPipeline = device.newRenderPipelineStateWithDescriptor(renderDescriptor)
        } catch {
            fatalError(String(format: "newRenderPipelineStateWithDescriptor failed: %s", error))
        }
    }

    private func newComputePipelineStateWithFunction(_ function: MTLFunction, linkedFunctions: [MTLFunction]) -> MTLComputePipelineState {
        var mtlLinkedFunctions: MTLLinkedFunctions
        var pipeline:           MTLComputePipelineState

        if linkedFunctions {
            mtlLinkedFunctions = [MTLLinkedFunctions]()
            mtlLinkedFunctions.functions = linkedFunctions
        }

        var descriptor = [MTLComputePipelineDescriptor]()
        descriptor.computeFunction                                 = function
        descriptor.linkedFunctions                                 = mtlLinkedFunctions
        descriptor.threadGroupSizeIsMultipleOfThreadExecutionWidth = true

        try {
            pipeline = device.newComputePipelineStateWithDescriptor(descriptor, options: 0, reflection: nil)
        } catch {
            fatalError(String(format: "newComputePipelineStateWithDescriptor failed: %s", error))
        }

        return pipeline
    }

    private func specializedFunctionWithName(_ name: String) -> MTLFunction {
        var constants             = MTLFunctionConstantValues()
        var resourcesStride: UInt = 0
        var function: MTLFunction

        constants.setConstantValue(&resourcesStride, type: MTLDataTypeUInt, atIndex: 0)
        constants.setConstantValue(&useIntersectionFunctions, type: MTLDataTypeBool, atIndex: 1)
        constants.setConstantValue(&usePerPrimitiveData, type: MTLDataTypeBool, atIndex: 2)

        try {
            function = library.newFunctionWithName(name, constantValues: constants)
        } catch {
            fatalError(String(format: "newFunctionWithName failed: %s", error))
        }

        return function
    }

    private func newArgumentEncoderForResources(_ resources: [MTLResource]) -> MTLArgumentEncoder {
        let arguments = [MTLArgumentDescriptor]()

        for resource in resources {
            let argumentDescriptor = MTLArgumentDescriptor()
            argumentDescriptor.index  = arguments.count
            argumentDescriptor.access = MTLArgumentAccessReadOnly

            if resource.conforms(to: MTLBuffer) {
                argumentDescriptor.dataType = MTLDataTypePointer
            } else {
                if resource.conforms(to: MTLTexture) {
                    let texture = resource as! MTLTexture

                    argumentDescriptor.dataType    = MTLDataTypeTexture
                    argumentDescriptor.textureType = texture.textureType
                }
            }

            arguments.append(argumentDescriptor)
        }

        return device.newArgumentEncoderWithArguments(arguments)
    }

    private func newAccelerationStructureWithDescriptor(_ descriptor: MTLAccelerationStructureDescriptor) -> MTLAccelerationStructure {
        let accelSizes            = device.accelerationStructureSizesWithDescriptor(descriptor)
        let accelerationStructure = device.newAccelerationStructureWithSize(accelSizes.accelerationStructureSize)

        let scratchBuffer         = device.newBufferWithLength(accelSizes.buildScratchBufferSize, options: MTLResourceOptions.storageModePrivate)

        let commandBuffer         = queue.commandBuffer()
        let commandEncoder        = commandBuffer.accelerationStructureCommandEncoder()

        let compactedSizeBuffer   = device.newBufferWithLength(sizeof(UInt32), options: MTLResourceOptions.storageModeShared)

        commandEncoder.buildAccelerationStructure(accelerationStructure, descriptor: descriptor, scratchBuffer: scratchBuffer, scratchBufferOffset: 0)
        commandEncoder.writeCompactedAccelerationStructureSize(accelerationStructure, toBuffer:compactedSizeBuffer)

        commandEncoder.endEncoding()
        commandBuffer.commit()

        commandBuffer.waitUntilCompleted()

        let compactedSize: UInt            = compactedSizeBuffer.contents.load(as: UInt.self)
        let compactedAccelerationStructure = device.newAccelerationStructureWithSize(compactedSize)

        commandBuffer  = queue.commandBuffer()
        commandEncoder = commandBuffer.accelerationStructureCommandEncoder()
        commandEncoder.copyAndCompactAccelerationStructure(accelerationStructure, toAccelerationStructure: compactedAccelerationStructure)

        commandEncoder.endEncoding()
        commandBuffer.commit()

        return compactedAccelerationStructure
    }
}
