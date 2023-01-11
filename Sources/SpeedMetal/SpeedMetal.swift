import MetalKit
import SwiftUI

struct SMView: UIViewRepresentable {
    var lineUp: LineUp
    var framesToRender: UInt32
    
    init(_ lineUp: LineUp, _ framesToRender: UInt32) {print("init")
        self.lineUp         = lineUp
        self.framesToRender = framesToRender
    }
    
    func makeCoordinator() -> Renderer {
        guard
            let device = MTLCreateSystemDefaultDevice(),
            device.supportsFamily(.metal3)
        else {
            fatalError("no Metal 3 capable GPU available")
        }
        let stage = Stage.hoistCornellBox(lineUp: lineUp, device: device)
        return Renderer(device: device, stage: stage)
    }
    
    func makeUIView(context: Context) -> MTKView {
        let view = MTKView(frame: .zero, device: context.coordinator.device)
        view.backgroundColor  = .black
        view.colorPixelFormat = .rgba16Float
        view.delegate         = context.coordinator
        return view
    }

    func updateUIView(_ view: MTKView, context: Context) {
        let stage = Stage.hoistCornellBox(lineUp: lineUp, device: view.device!)
//        context.coordinator.stage = stage
//        context.coordinator.reset()
        context.coordinator.framesToRender = framesToRender
    }
}

@main
struct SpeedMetal: App {
    @State var lineUp = LineUp.threeByThree
    @State var framesToRender: UInt32 = 1

    var body: some Scene {
        WindowGroup {
            SMView(lineUp, framesToRender)
            HStack {
                Button {
                    framesToRender += 1
                } label: {
                    Text("1x")
                        .font(.title2)
                }
                Button {
                    framesToRender += 10
                } label: {
                    Text("10x")
                        .font(.title2)
                }
                Button {
                    framesToRender += 100
                } label: {
                    Text("100x")
                        .font(.title2)
                }
                Button {
                    framesToRender = 1
                    lineUp = .oneByOne
                } label: {
                    Image(systemName: "square")
                        .resizable()
                        .frame(width: 42, height: 42)
                }
                .disabled(lineUp == .oneByOne)
                Button {
                    framesToRender = 1
                    lineUp = .twoByTwo
                } label: {
                    Image(systemName: "square.grid.2x2")
                        .resizable()
                        .frame(width: 42, height: 42)
                }
                .disabled(lineUp == .twoByTwo)
                Button {
                    framesToRender = 1
                    lineUp = .threeByThree
                } label: {
                    Image(systemName: "square.grid.3x3")
                        .resizable()
                        .frame(width: 42, height: 42)
                }
                .disabled(lineUp == .threeByThree)
            }
            .padding(.bottom, 8)
        }
    }
}
