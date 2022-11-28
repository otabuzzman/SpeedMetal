import SwiftUI

import MetalKit
import simd

class Renderer: NSObject, MTKViewDelegate {
    private var device: MTLDevice
    private var stage:  Stage
    
    private let maxFramesInFlight   = 3
    private let alignedUniformsSize = (MemoryLayout<Uniforms>.size + 255) & ~255

    private var queue:   MTLCommandQueue?
    private var library: MTLLibrary?

    private var uniformBuffer: MTLBuffer?

    private var instanceAccelerationStructure:   MTLAccelerationStructure?
    private var primitiveAccelerationStructures: NSMutableArray!

    private var raytracingPipeline:        MTLComputePipelineState?
    private var copyPipeline:              MTLRenderPipelineState?

    private var accumulationTargets      = [MTLTexture]()
    private var randomTexture:             MTLTexture?

    private var resourceBuffer:            MTLBuffer?
    private var instanceBuffer:            MTLBuffer?

    private var intersectionFunctionTable: MTLIntersectionFunctionTable?

    private var sem:  DispatchSemaphore
    private var size: CGSize             = .zero
    private var uniformBufferOffset      = 0
    private var uniformBufferIndex       = 0

    private var frameIndex: UInt         = 0

    private var resourcesStride: UInt    = 0
    private var useIntersectionFunctions = false
    private var usePerPrimitiveData      = false

    init(device: MTLDevice, stage: Stage) { // initWithDevice
        self.device = device
        self.stage = stage

        sem = DispatchSemaphore(value: maxFramesInFlight)

        super.init()

        loadMetal()
        createBuffers()
        createAccelerationStructures()
        createPipelines()
    }

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) -> Void {
        self.size = size

        let textureDescriptor         = MTLTextureDescriptor()
        textureDescriptor.pixelFormat = MTLPixelFormat.rgba32Float
        textureDescriptor.textureType = .type2D
        textureDescriptor.width       = Int(size.width)
        textureDescriptor.height      = Int(size.height)
        textureDescriptor.storageMode = .private
        textureDescriptor.usage       = .shaderWrite

        if accumulationTargets.count == 0 {
            accumulationTargets.append(device.makeTexture(descriptor: textureDescriptor)!)
            accumulationTargets.append(device.makeTexture(descriptor: textureDescriptor)!)
        } else {
            accumulationTargets[0] = device.makeTexture(descriptor: textureDescriptor)!
            accumulationTargets[1] = device.makeTexture(descriptor: textureDescriptor)!
        }

        textureDescriptor.pixelFormat = .r32Uint
        textureDescriptor.usage       = .shaderRead
        textureDescriptor.storageMode = .shared

        randomTexture = device.makeTexture(descriptor: textureDescriptor)!

        var randomValues = [UInt32](repeating: 0, count: Int(size.width) * Int(size.height))

        for i in 0..<Int(size.width * size.height) {
            randomValues[i] = UInt32.random(in: 0..<(1024 * 1024))
        }

        randomTexture!.replace(region: MTLRegionMake2D(0, 0, Int(size.width), Int(size.height)), mipmapLevel: 0, withBytes: randomValues, bytesPerRow: MemoryLayout<UInt32>.size * Int(size.width))

        frameIndex = 0
    }

    private func updateUniforms() -> Void {
        uniformBufferOffset = alignedUniformsSize * uniformBufferIndex

        var uniforms = uniformBuffer!.contents().load(fromByteOffset: uniformBufferOffset, as: Uniforms.self) 

        let position = stage.cameraPosition
        let target   = stage.cameraTarget
        var up       = stage.cameraUp

        let forward  = simd_normalize(target - position)
        let right    = simd_normalize(simd_cross(forward, up))
        up           = simd_normalize(simd_cross(right, forward))

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

    func draw(in view: MTKView) -> Void { // drawInMTKView
        sem.wait()

        let commandBuffer = queue!.makeCommandBuffer()
        commandBuffer!.addCompletedHandler() { [self] _ in
            sem.signal()
        }

        updateUniforms()

        let width  = Int(size.width)
        let height = Int(size.height)

        let threadsPerThreadgroup = MTLSizeMake(8, 8, 1)
        let threadgroups          = MTLSizeMake((width  + threadsPerThreadgroup.width  - 1) / threadsPerThreadgroup.width, (height + threadsPerThreadgroup.height - 1) / threadsPerThreadgroup.height, 1)

        let computeEncoder = commandBuffer!.makeComputeCommandEncoder()

        computeEncoder!.setBuffer(uniformBuffer, offset: uniformBufferOffset, index: 0)
        if (!usePerPrimitiveData) {
            computeEncoder!.setBuffer(resourceBuffer, offset: 0, index: 1)
        }
        computeEncoder!.setBuffer(instanceBuffer, offset: 0, index: 2)
        computeEncoder!.setBuffer(stage.lightBuffer, offset: 0, index: 3)

        computeEncoder!.setAccelerationStructure(instanceAccelerationStructure, bufferIndex: 4)
        computeEncoder!.setIntersectionFunctionTable(intersectionFunctionTable, bufferIndex: 5)

        computeEncoder!.setTexture(randomTexture, index: 0)
        computeEncoder!.setTexture(accumulationTargets[0], index: 1)
        computeEncoder!.setTexture(accumulationTargets[1], index: 2)

        for geometry in stage.geometries {
            for resource in (geometry as! Geometry).resources() {
                computeEncoder!.useResource(resource, usage: MTLResourceUsage.read)
            }
        }

        for primitiveAccelerationStructure in primitiveAccelerationStructures {
            computeEncoder!.useResource(primitiveAccelerationStructure as! MTLResource, usage: .read)
        }

        computeEncoder!.setComputePipelineState(raytracingPipeline!)

        computeEncoder!.dispatchThreadgroups(threadgroups, threadsPerThreadgroup: threadsPerThreadgroup)
        computeEncoder!.endEncoding()

        accumulationTargets.swapAt(0, 1)

        if view.currentDrawable != nil {
            let renderPassDescriptor = MTLRenderPassDescriptor()
            renderPassDescriptor.colorAttachments[0].texture    = view.currentDrawable?.texture
            renderPassDescriptor.colorAttachments[0].loadAction = .clear
            renderPassDescriptor.colorAttachments[0].clearColor = MTLClearColorMake(0.0, 0.0, 0.0, 1.0)

            // Create a render command encoder.
            let renderEncoder = commandBuffer!.makeRenderCommandEncoder(descriptor: renderPassDescriptor)
            renderEncoder!.setRenderPipelineState(copyPipeline!)
            renderEncoder!.setFragmentTexture(accumulationTargets[0], index: 0)
            renderEncoder!.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 6)

            renderEncoder!.endEncoding()

            commandBuffer!.present(view.currentDrawable!)
        }

        commandBuffer!.commit()
    }

    private func loadMetal() -> Void {
        library = try! device.makeLibrary(source: shadersMetal, options: nil)
        queue   = device.makeCommandQueue()!
    }

    private func createBuffers() -> Void {
        let uniformBufferSize = alignedUniformsSize * maxFramesInFlight
        uniformBuffer = device.makeBuffer(length: uniformBufferSize)

        stage.uploadToBuffers()

        resourcesStride = 0

        for geometry in stage.geometries {
            let geometry = geometry as! Geometry
            // Metal 3
            if #available(iOS 16, macOS 13, *) {
                if geometry.resources().count * MemoryLayout<UInt64>.size > resourcesStride {
                    resourcesStride = UInt(geometry.resources().count * MemoryLayout<UInt64>.size)
                }
            } else {
                let encoder = newArgumentEncoderForResources(geometry.resources())

                if encoder.encodedLength > resourcesStride {
                    resourcesStride = UInt(encoder.encodedLength)
                }
            }
        }

        resourceBuffer = device.makeBuffer(length: Int(resourcesStride) * stage.geometries.count)!

        for geometryIndex in 0..<stage.geometries.count {
            let geometry = stage.geometries[geometryIndex] as! Geometry

            // Metal 3
            if #available(iOS 16, macOS 13, *) { 
                let resources = geometry.resources()

                let resourceHandles = resourceBuffer!.contents() + Int(resourcesStride) * geometryIndex
                
                for argumentIndex in 0..<resources.count {
                    let resource = resources[argumentIndex]

                    if resource.conforms(to: MTLBuffer.self) {
                        resourceHandles.storeBytes(of: (resource as! MTLBuffer).gpuAddress, toByteOffset: argumentIndex * MemoryLayout<UInt64>.size, as: UInt64.self)
                    } else {
                        if resource.conforms(to: MTLTexture.self) {
                            resourceHandles.storeBytes(of: (resource as! MTLTexture).gpuResourceID, toByteOffset: argumentIndex * MemoryLayout<MTLResourceID>.size, as: MTLResourceID.self)
                        }
                    }
                }
            } else {
                let encoder = newArgumentEncoderForResources(geometry.resources())
                encoder.setArgumentBuffer(resourceBuffer, offset: Int(resourcesStride) * geometryIndex)

                for argumentIndex in 0..<geometry.resources().count {
                    let resource = geometry.resources()[argumentIndex]

                    if resource.conforms(to: MTLBuffer.self) {
                        encoder.setBuffer((resource as! MTLBuffer), offset: 0, index: argumentIndex)
                    } else {
                        if resource.conforms(to: MTLTexture.self) {
                            encoder.setTexture((resource as! MTLTexture), index: argumentIndex)
                        }
                    }
                }
            }
        }
    }

    private func createAccelerationStructures() -> Void {
        primitiveAccelerationStructures = []

        for i in 0..<stage.geometries.count {
            let mesh = stage.geometries[i] as! Geometry

            let geometryDescriptor = mesh.geometryDescriptor()
            geometryDescriptor.intersectionFunctionTableOffset = i

            let accelDescriptor = MTLPrimitiveAccelerationStructureDescriptor()
            accelDescriptor.geometryDescriptors = [geometryDescriptor]

            let accelerationStructure = newAccelerationStructureWithDescriptor(accelDescriptor)
            primitiveAccelerationStructures.add(accelerationStructure)
        }

        let instanceBuffer = device.makeBuffer(length: MemoryLayout<MTLAccelerationStructureInstanceDescriptor>.size * stage.instances.count)

        let instanceDescriptors = instanceBuffer!.contents().bindMemory(to: MTLAccelerationStructureInstanceDescriptor.self, capacity: stage.instances.count)
        for instanceIndex in 0..<stage.instances.count {
            let instance = stage.instances[instanceIndex]
            
            let geometryIndex = stage.geometries.index(of: instance.geometry)
            
            instanceDescriptors[instanceIndex].accelerationStructureIndex      = UInt32(geometryIndex)
            instanceDescriptors[instanceIndex].options                         = instance.geometry.intersectionFunctionName.isEmpty ? .opaque : .nonOpaque
            instanceDescriptors[instanceIndex].intersectionFunctionTableOffset = 0
            instanceDescriptors[instanceIndex].mask                            = UInt32(instance.mask)
            instanceDescriptors[instanceIndex].transformationMatrix            = MTLPackedFloat4x3(instance.transform)
        }

        let accelDescriptor = MTLInstanceAccelerationStructureDescriptor()
        accelDescriptor.instancedAccelerationStructures = primitiveAccelerationStructures as? [any MTLAccelerationStructure]
        accelDescriptor.instanceCount                   = stage.instances.count
        accelDescriptor.instanceDescriptorBuffer        = instanceBuffer

        instanceAccelerationStructure = newAccelerationStructureWithDescriptor(accelDescriptor)
    }

    private func createPipelines() -> Void {
        useIntersectionFunctions = false

        // Metal 3
        if #available(iOS 16, macOS 13, *) {
            usePerPrimitiveData = true
        } else {
            usePerPrimitiveData = false
        }

        for geometry in stage.geometries {
            if !(geometry as! Geometry).intersectionFunctionName.isEmpty {
                useIntersectionFunctions = true

                break
            }
        }

        var intersectionFunctions: [String: MTLFunction] = [:]

        for geometry in stage.geometries {
            let geometry = geometry as! Geometry
            if geometry.intersectionFunctionName.isEmpty || intersectionFunctions.index(forKey: geometry.intersectionFunctionName) == nil {
                continue
            }

            let intersectionFunction = specializedFunctionWithName(geometry.intersectionFunctionName)
            intersectionFunctions[geometry.intersectionFunctionName] = intersectionFunction
        }

        let raytracingFunction = specializedFunctionWithName("raytracingKernel")

        let raytracingPipeline = newComputePipelineStateWithFunction(raytracingFunction, linkedFunctions: Array<MTLFunction>(intersectionFunctions.values))

        if useIntersectionFunctions {
            let intersectionFunctionTableDescriptor = MTLIntersectionFunctionTableDescriptor()
            intersectionFunctionTableDescriptor.functionCount = stage.geometries.count

            let intersectionFunctionTable = raytracingPipeline.makeIntersectionFunctionTable(descriptor: intersectionFunctionTableDescriptor)

            if !usePerPrimitiveData {
                intersectionFunctionTable!.setBuffer(resourceBuffer, offset: 0, index: 0)
            }

            for geometryIndex in 0..<stage.geometries.count {
                let geometry = stage.geometries[geometryIndex] as! Geometry

                if !geometry.intersectionFunctionName.isEmpty {
                    let intersectionFunction = intersectionFunctions[geometry.intersectionFunctionName]
                    let handle               = raytracingPipeline.functionHandle(function: intersectionFunction!)
                    intersectionFunctionTable!.setFunction(handle, index: geometryIndex)
                }
            }
        }

        let renderDescriptor = MTLRenderPipelineDescriptor()
        renderDescriptor.vertexFunction                  = library!.makeFunction(name: "copyVertex")
        renderDescriptor.fragmentFunction                = library!.makeFunction(name: "copyFragment")
        renderDescriptor.colorAttachments[0].pixelFormat = .rgba16Float

        do {
            copyPipeline = try device.makeRenderPipelineState(descriptor: renderDescriptor)
        } catch {
            fatalError(String(format: "makeRenderPipelineState failed: \(error)"))
        }
    }

    private func newComputePipelineStateWithFunction(_ function: MTLFunction, linkedFunctions: [MTLFunction]) -> MTLComputePipelineState {
        var mtlLinkedFunctions: MTLLinkedFunctions?
        var pipeline:           MTLComputePipelineState

        if !linkedFunctions.isEmpty {
            mtlLinkedFunctions = MTLLinkedFunctions()
            mtlLinkedFunctions!.functions = linkedFunctions
        }

        let descriptor = MTLComputePipelineDescriptor()
        descriptor.computeFunction                                 = function
        descriptor.linkedFunctions                                 = mtlLinkedFunctions
        descriptor.threadGroupSizeIsMultipleOfThreadExecutionWidth = true

        do {
            pipeline = try device.makeComputePipelineState(descriptor: descriptor, options: MTLPipelineOption(), reflection: nil)
        } catch {
            fatalError(String(format: "makeComputePipelineState failed: \(error)"))
        }

        return pipeline
    }

    private func specializedFunctionWithName(_ name: String) -> MTLFunction {
        let constants             = MTLFunctionConstantValues()
        var resourcesStride: UInt = 0
        var function: MTLFunction

        constants.setConstantValue(&resourcesStride, type: .uint, index: 0)
        constants.setConstantValue(&useIntersectionFunctions, type: .bool, index: 1)
        constants.setConstantValue(&usePerPrimitiveData, type: .bool, index: 2)

        do {
            function = try library!.makeFunction(name: name, constantValues: constants)
        } catch {
            fatalError(String(format: "makeFunction failed: \(error)"))
        }

        return function
    }

    private func newArgumentEncoderForResources(_ resources: [MTLResource]) -> MTLArgumentEncoder {
        var arguments = [MTLArgumentDescriptor]()

        for resource in resources {
            let argumentDescriptor = MTLArgumentDescriptor()
            argumentDescriptor.index  = arguments.count
            argumentDescriptor.access = .readOnly

            if resource.conforms(to: MTLBuffer.self) {
                argumentDescriptor.dataType = .pointer
            } else {
                if resource.conforms(to: MTLTexture.self) {
                    let texture = resource as! MTLTexture

                    argumentDescriptor.dataType    = .texture
                    argumentDescriptor.textureType = texture.textureType
                }
            }

            arguments.append(argumentDescriptor)
        }

        return device.makeArgumentEncoder(arguments: arguments)!
    }

    private func newAccelerationStructureWithDescriptor(_ descriptor: MTLAccelerationStructureDescriptor) -> MTLAccelerationStructure {
        let accelSizes            = device.accelerationStructureSizes(descriptor: descriptor)
        let accelerationStructure = device.makeAccelerationStructure(size: accelSizes.accelerationStructureSize)

        let scratchBuffer         = device.makeBuffer(length: accelSizes.buildScratchBufferSize, options: MTLResourceOptions.storageModePrivate)

        var commandBuffer         = queue!.makeCommandBuffer()
        var commandEncoder        = commandBuffer!.makeAccelerationStructureCommandEncoder()

        let compactedSizeBuffer   = device.makeBuffer(length: MemoryLayout<UInt32>.size, options: MTLResourceOptions.storageModeShared)

        commandEncoder!.build(accelerationStructure: accelerationStructure!, descriptor: descriptor, scratchBuffer: scratchBuffer!, scratchBufferOffset: 0)
        commandEncoder!.writeCompactedSize(accelerationStructure: accelerationStructure!, buffer: compactedSizeBuffer!, offset: 0)

        commandEncoder!.endEncoding()
        commandBuffer!.commit()

        commandBuffer!.waitUntilCompleted()

        let compactedSize                  = compactedSizeBuffer!.contents().load(as: UInt32.self)
        let compactedAccelerationStructure = device.makeAccelerationStructure(size: Int(compactedSize))

        commandBuffer  = queue!.makeCommandBuffer()
        commandEncoder = commandBuffer!.makeAccelerationStructureCommandEncoder()
        commandEncoder!.copyAndCompact(sourceAccelerationStructure: accelerationStructure!, destinationAccelerationStructure: compactedAccelerationStructure!)

        commandEncoder!.endEncoding()
        commandBuffer!.commit()

        return compactedAccelerationStructure!
    }
}

// https://developer.apple.com/forums/thread/653267
extension MTLPackedFloat4x3 {
    init(_ matrix4x4: matrix_float4x4) {
        self.init(columns: (
            MTLPackedFloat3(matrix4x4[0]),
            MTLPackedFloat3(matrix4x4[1]),
            MTLPackedFloat3(matrix4x4[2]),
            MTLPackedFloat3(matrix4x4[3])
        ))
    }
}

extension MTLPackedFloat3 {
    init(_ vector4: vector_float4) {
        self.init()
        self.elements = (vector4[0], vector4[1], vector4[2])
    }
}
