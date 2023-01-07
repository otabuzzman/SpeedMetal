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
    var content: Content

    init(content: () -> Content) {
        self.content = content()
    }

    func makeUIView(context: Context) -> Content {
        content
    }

    func updateUIView(_ uiView: Content, context: Context) {
        uiView.isPaused = true
        
        let stage = Stage.hoistCornellBox(device: uiView.device!)
        (uiView.delegate as! Renderer).reset(stage: stage)

        uiView.isPaused = false
    }
}

@main
struct SpeedMetal: App {
    @StateObject var options = RendererOptions()

    var body: some Scene {
        WindowGroup {
            SMViewAdapter() {
                SMView() { this in
                    let stage = Stage.hoistCornellBox(device: this.device!)

                    this.backgroundColor  = .black
                    this.colorPixelFormat = .rgba16Float
                    
                    this.renderer = Renderer(device: this.device!, stage: stage, options: options)
                    this.delegate = this.renderer
                }
            }
            HStack {
                Button {
                    options.framesToRender = 1
                } label: {
                    Text("1x")
                        .frame(width: 42, height: 42)
                }
                Button {
                    options.framesToRender = 10
                } label: {
                    Text("10x")
                        .frame(width: 42, height: 42)
                }
                Button {
                    options.framesToRender = 100
                } label: {
                    Text("100x")
                        .frame(width: 42, height: 42)
                }
                Button {
                    options.lineUp = .oneByOne
                } label: {
                    Image(systemName: options.lineUp == .oneByOne ? "square.fill" : "square")
                        .resizable()
                        .frame(width: 42, height: 42)
                }
                .disabled(options.lineUp == .oneByOne)
                Button {
                    options.lineUp = .twoByTwo
                } label: {
                    Image(systemName: options.lineUp == .twoByTwo ? "square.grid.2x2.fill" : "square.grid.2x2")
                        .resizable()
                        .frame(width: 42, height: 42)
                }
                .disabled(options.lineUp == .twoByTwo)
                Button {
                    options.lineUp = .threeByThree
                } label: {
                    Image(systemName: options.lineUp == .threeByThree ? "square.grid.3x3.fill" : "square.grid.3x3")
                        .resizable()
                        .frame(width: 42, height: 42)
                }
                .disabled(options.lineUp == .threeByThree)
         }
         .padding(.bottom, 8)
        }
    }
}
