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
    @EnvironmentObject var control: RendererControl

    var content: Content

    init(content: () -> Content) {
        self.content = content()
    }

    func makeUIView(context: Context) -> Content {
        content
    }

    func updateUIView(_ uiView: Content, context: Context) {
        uiView.isPaused = true

        let stage = Stage.hoistCornellBox(lineUp: control.lineUp, device: uiView.device!)
        (uiView.delegate as! Renderer).reset(stage: stage)

        uiView.isPaused = false
    }
}

@main
struct SpeedMetal: App {
    @StateObject var control = RendererControl()

    var body: some Scene {
        WindowGroup {
            SMViewAdapter() {
                SMView() { this in
                    let stage = Stage.hoistCornellBox(lineUp: .oneByOne, device: this.device!)

                    this.backgroundColor  = .black
                    this.colorPixelFormat = .rgba16Float

                    this.renderer = Renderer(device: this.device!, stage: stage, control: control)
                    this.delegate = this.renderer
                }
            }
            .environmentObject(control)
            HStack {
                Button {
                    control.lineUp = .oneByOne
                } label: {
                    Image(systemName: control.lineUp == .oneByOne ? "square.fill" : "square")
                        .resizable()
                        .frame(width: 42, height: 42)
                }
                .disabled(control.lineUp == .oneByOne)
                Button {
                    control.lineUp = .twoByTwo
                } label: {
                    Image(systemName: control.lineUp == .twoByTwo ? "square.grid.2x2.fill" : "square.grid.2x2")
                        .resizable()
                        .frame(width: 42, height: 42)
                }
                .disabled(control.lineUp == .twoByTwo)
                Button {
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
