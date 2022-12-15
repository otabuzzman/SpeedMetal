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

struct MTKViewRepresentable<Content>: UIViewRepresentable where Content: MTKView {
    var isPaused: Bool
    var content: Content

    public init(_ isPaused: Bool, closure: () -> Content) {
        self.isPaused = isPaused
        content = closure()
    }

    public func makeUIView(context: Context) -> Content {
        content
    }

    public func updateUIView(_ uiView: Content, context: Context) {
        uiView.isPaused = isPaused
    }
}

@main
struct SpeedMetal: App {
    @State var isPaused = false
    
    var body: some Scene {
        WindowGroup {
            MTKViewRepresentable(isPaused) {
                SMView() { this in
                    let stage = Stage.hoistCornellBox(device: this.device!, useIntersectionFunctions: true)
                    
                    this.backgroundColor  = .black
                    this.colorPixelFormat = .rgba16Float
                        
                    this.renderer = Renderer(device: this.device!, stage: stage)
                    this.delegate = this.renderer
                }
            }
            HStack {
                Button {
                    isPaused.toggle()
                } label: {
                    Image(systemName: isPaused ? "play.circle" : "pause.circle")
                        .resizable()
                        .frame(width: 42, height: 42)
                }
            }.padding(.bottom, 8)
        }
    }
}
