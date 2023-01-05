import MetalKit
import SwiftUI

enum SMViewControl: Equatable {
    case suspend
    case carryOn
    case lineUp(LineUp)
}

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

struct SMViewAdapter<Content>: UIViewRepresentable where Content: MTKView {
    var control: SMViewControl
    var content: Content

    init(_ control: SMViewControl, content: () -> Content) {
        self.control = control
        self.content = content()
    }

    func makeUIView(context: Context) -> Content {
        content
    }

    func updateUIView(_ uiView: Content, context: Context) {
        switch control {
        case .suspend:
            uiView.isPaused = true
        case .carryOn:
            uiView.isPaused = false
        case .lineUp(let lineUp):
            uiView.isPaused = true
            let renderer = uiView.delegate as! Renderer
            
            let stage = Stage.hoistCornellBox(lineUp: lineUp, device: uiView.device!)
            renderer.rearrange(stage: stage)
            
            renderer.mtkView(uiView, drawableSizeWillChange: uiView.drawableSize)
            uiView.isPaused = false
        }
    }
}

@main
struct SpeedMetal: App {
    @State var control: SMViewControl = .carryOn

    var body: some Scene {
        WindowGroup {
            SMViewAdapter(control) {
                SMView() { this in
                    let stage = Stage.hoistCornellBox(lineUp: .oneByOne, device: this.device!)

                    this.backgroundColor  = .black
                    this.colorPixelFormat = .rgba16Float
                        
                    this.renderer = Renderer(device: this.device!, stage: stage)
                    this.delegate = this.renderer
                }
            }
            HStack {
                Button {
                    control = .lineUp(.oneByOne)
                } label: {
                    Image(systemName: control == .lineUp(.oneByOne) ? "square.fill" : "square")
                        .resizable()
                        .frame(width: 42, height: 42)
                }
                Button {
                    control = .lineUp(.twoByTwo)
                } label: {
                    Image(systemName: control == .lineUp(.twoByTwo) ? "square.grid.2x2.fill" : "square.grid.2x2")
                        .resizable()
                        .frame(width: 42, height: 42)
                }
                Button {
                    control = .lineUp(.threeByThree)
                } label: {
                    Image(systemName: control == .lineUp(.threeByThree) ? "square.grid.3x3.fill" : "square.grid.3x3")
                        .resizable()
                        .frame(width: 42, height: 42)
                }
         }
         .padding(.bottom, 8)
        }
    }
}
