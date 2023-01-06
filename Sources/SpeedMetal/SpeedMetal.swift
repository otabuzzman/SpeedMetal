import MetalKit
import SwiftUI

class SMView: MTKView {
    var renderer: Renderer!

    init(configure: (SMView) -> ()) {
        guard
            let device = MTLCreateSystemDefaultDevice(),
            device.supportsFamily(.metal3)
        else {
            fatalError("no Metal 3 capable GPU available")
        }
        super.init(frame: .zero, device: device)

        configure(self)
    }

    required init(coder: NSCoder) {
        super.init(coder: coder)
    }
}

struct RendererControl {
    enum Command {
        case setLineUp
        case setFramesToRender
        case setUsePerPrimitiveData
        case setUpscaleFactor
    }

    var command: Command

    var lineUp: LineUp
    var framesToRender: Int
    var usePerPrimitiveData: Bool
    var upscaleFactor: Float
}

struct SMViewAdapter<Content>: UIViewRepresentable where Content: MTKView {
    var control: RendererControl
    var content: Content

    init(control: RendererControl, content: () -> Content) {
        self.control = control
        self.content = content()
    }

    func makeUIView(context: Context) -> Content {
        content
    }

    func updateUIView(_ uiView: Content, context: Context) {
        uiView.isPaused = true

        switch control.command {
        case .setLineUp:
            let stage = Stage.hoistCornellBox(lineUp: control.lineUp, device: uiView.device!)
            (uiView.delegate as! Renderer).reset(stage: stage)
        case .setFramesToRender:
            (uiView.delegate as! Renderer).framesToRender = control.framesToRender
        case .setUsePerPrimitiveData:
            (uiView.delegate as! Renderer).usePerPrimitiveData = control.usePerPrimitiveData
        case .setUpscaleFactor:
            (uiView.delegate as! Renderer).upscaleFactor = control.upscaleFactor
        }

        uiView.isPaused = false
    }
}

@main
struct SpeedMetal: App {
    @StateObject var control: RendererControl = .upscaleFactor(1.0)

    var body: some Scene {
        WindowGroup {
            SMViewAdapter(control: control) {
                SMView() { this in
                    let stage = Stage.hoistCornellBox(lineUp: .oneByOne, device: this.device!)

                    this.backgroundColor  = .black
                    this.colorPixelFormat = .rgba16Float

                    this.renderer = Renderer(device: this.device!, stage: stage, control: control)
                    this.delegate = this.renderer
                }
            }
            HStack {
                Button {
                    control.command = .framesToRender
                    control.framesToRender = 1
                } label: {
                    Text("1x")
                        .frame(width: 42, height: 42)
                }
                Button {
                    control.command = .framesToRender
                    control.framesToRender = 10
                } label: {
                    Text("10x")
                        .frame(width: 42, height: 42)
                }
                Button {
                    control.command = .framesToRender
                    control.framesToRender = 100
                } label: {
                    Text("100x")
                        .frame(width: 42, height: 42)
                }
                Button {
                    control.command = .lineUp
                    control.lineUp = .oneByOne
                } label: {
                    Image(systemName: control.lineUp == .oneByOne ? "square.fill" : "square")
                        .resizable()
                        .frame(width: 42, height: 42)
                }
                .disabled(control.lineUp == .oneByOne)
                Button {
                    control.command = .lineUp
                    control.lineUp = .twoByTwo
                } label: {
                    Image(systemName: control.lineUp == .twoByTwo ? "square.grid.2x2.fill" : "square.grid.2x2")
                        .resizable()
                        .frame(width: 42, height: 42)
                }
                .disabled(control.lineUp == .twoByTwo)
                Button {
                    control.command = .lineUp
                    control.lineUp = .threeByThree
                } label: {
                    Image(systemName: control.lineUp == .threeByThree ? "square.grid.3x3.fill" : "square.grid.3x3")
                        .resizable()
                        .frame(width: 42, height: 42)
                }
                .disabled(control.lineUp == .threeByThree)
         }
         .padding(.bottom, 8)
        }
    }
}
