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

struct SMViewAdapter<Content>: UIViewRepresentable where Content: MTKView {
    var lineUp: LineUp
    var content: Content

    init(_ lineUp: LineUp, content: () -> Content) {
        self.lineUp = lineUp
        self.content = content()
    }

    func makeUIView(context: Context) -> Content {
        content
    }

    func updateUIView(_ uiView: Content, context: Context) {
        let stage = Stage.hoistCornellBox(lineUp: lineUp, device: uiView.device!)
        (uiView.delegate as! Renderer).reset(stage: stage)
    }
}

@main
struct SpeedMetal: App {
    @StateObject var options = RendererOptions()

    var body: some Scene {
        WindowGroup {
            SMViewAdapter(options.lineUp) {
                SMView() { this in
                    this.backgroundColor  = .black
                    this.colorPixelFormat = .rgba16Float

                    let stage = Stage.hoistCornellBox(device: this.device!)
                    this.renderer = Renderer(device: this.device!, stage: stage, options: options)
                    this.delegate = this.renderer
                }
            }
            HStack {
                Button {
                    options.framesToRender += 1
                } label: {
                    Text("1x")
                        .font(.title2)
                }
                Button {
                    options.framesToRender += 10
                } label: {
                    Text("10x")
                        .font(.title2)
                }
                Button {
                    options.framesToRender += 100
                } label: {
                    Text("100x")
                        .font(.title2)
                }
                Button {
                    options.framesToRender = 1
                    options.lineUp = .oneByOne
                } label: {
                    Image(systemName: "square")
                        .resizable()
                        .frame(width: 42, height: 42)
                }
                .disabled(options.lineUp == .oneByOne)
                Button {
                    options.framesToRender = 1
                    options.lineUp = .twoByTwo
                } label: {
                    Image(systemName: "square.grid.2x2")
                        .resizable()
                        .frame(width: 42, height: 42)
                }
                .disabled(options.lineUp == .twoByTwo)
                Button {
                    options.framesToRender = 1
                    options.lineUp = .threeByThree
                } label: {
                    Image(systemName: "square.grid.3x3")
                        .resizable()
                        .frame(width: 42, height: 42)
                }
                .disabled(options.lineUp == .threeByThree)
            }
            .padding(.bottom, 8)
        }
    }
}
