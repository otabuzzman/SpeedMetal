import MetalKit
import SwiftUI

enum SMViewControl {
    case suspend
    case carryOn
}

class SMView: MTKView {
    var renderer: Renderer!

    init(configure: (SMView, InstancesGrid?) -> ()) {
        guard
            let device = MTLCreateSystemDefaultDevice(),
            device.supportsFamily(.metal3)
        else {
            fatalError("no Metal 3 capable GPU available")
        }
        super.init(frame: .zero, device: device)

        configure(self, nil)
    }

    required init(coder: NSCoder) {
        super.init(coder: coder)
    }
}

struct SMViewAdapter<Content>: UIViewRepresentable where Content: SMView {
    var control: SMViewControl
    var content: Content

    init(_ control: SMViewControl, closure: () -> Content) {
        self.control = control
        content = closure()
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
        }
    }
}

@main
struct SpeedMetal: App {
    @State var control: SMViewControl = .carryOn

    var body: some Scene {
        WindowGroup {
            SMViewAdapter(control) {
                SMView() { this, grid in
                    let stage = Stage.hoistCornellBox(device: this.device!)

                    this.backgroundColor  = .black
                    this.colorPixelFormat = .rgba16Float
                        
                    this.renderer = Renderer(device: this.device!, stage: stage)
                    this.delegate = this.renderer
                }
            }
            HStack {
                Button {
                    control = control == .suspend ? .carryOn : .suspend
                } label: {
                    Image(systemName: control == .suspend ? "play.circle" : "pause.circle")
                        .resizable()
                        .frame(width: 42, height: 42)
                }
         }
         .padding(.bottom, 8)
        }
    }
}
