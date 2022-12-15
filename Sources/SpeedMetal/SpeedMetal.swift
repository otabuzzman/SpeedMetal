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

struct CUIView<Content>: UIViewRepresentable where Content: UIView {
    var content: Content

    public init(closure: () -> Content) {
        content = closure()
    }

    public func makeUIView(context: Context) -> Content {
        return content
    }

    public func updateUIView(_ uiView: Content, context: Context) {
    }
}

@main
struct SpeedMetal: App {
    var body: some Scene {
        WindowGroup {
            CUIView() {
                SMView() { this in
                    let stage = Stage.makeCornellBox(device: this.device!, useIntersectionFunctions: true)

                    this.backgroundColor  = .black
                    this.colorPixelFormat = .rgba16Float

                    this.renderer = Renderer(device: this.device!, stage: stage)
                    this.delegate = this.renderer
                }
            }
        }
    }
}
