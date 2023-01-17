import MetalKit
import SwiftUI

enum SMViewControl {
    case none
    case lineUp
    case framesToRender
    case upscaleFactor
}

struct SMView: UIViewRepresentable {
    @Binding var control: SMViewControl
    var lineUp: LineUp
    @Binding var framesToRender: UInt32
    var upscaleFactor: Float
    @Binding var rendererTimes: RendererTimes
    @Binding var drawLoopEnabled: Bool

    func makeCoordinator() -> Renderer {
        guard
            let device = MTLCreateSystemDefaultDevice(),
            device.supportsFamily(.metal3)
        else {
            fatalError("no Metal 3 capable GPU available")
        }
        let stage = Stage.hoistCornellBox(lineUp: lineUp, device: device)
        return Renderer(stage: stage, device: device, enabled: $drawLoopEnabled, times: rendererTimes)
    }

    func makeUIView(context: Context) -> MTKView {
        let view = MTKView(frame: .zero, device: context.coordinator.device)
        view.backgroundColor  = .black
        view.colorPixelFormat = .rgba16Float
        view.delegate         = context.coordinator
        return view
    }

    func updateUIView(_ view: MTKView, context: Context) {
        switch control {
        case .none:
            return
        case .lineUp:
            let stage = Stage.hoistCornellBox(lineUp: lineUp, device: view.device!)
            context.coordinator.framesToRender = 1
            context.coordinator.stage          = stage
            framesToRender = 1
        case .framesToRender:
            context.coordinator.framesToRender = framesToRender
        case .upscaleFactor:
            context.coordinator.framesToRender = 1
            context.coordinator.upscaleFactor  = upscaleFactor
            framesToRender = 1
        }
        control = .none // prevent last command running after Renderer updates Bindings
        view.isPaused = false
    }
}

@main
struct SpeedMetal: App {
    @State var control = SMViewControl.none
    @State var lineUp  = LineUp.threeByThree
    @State var framesToRender: UInt32 = 1
    @State var upscaleFactor: Float   = 1.0
    @State var rendererTimes   = RendererTimes()
    @State var drawLoopEnabled = true

    var body: some Scene {
        WindowGroup {
            ZStack(alignment: .topLeading) {
                SMView(control: $control, lineUp: lineUp, framesToRender: $framesToRender, upscaleFactor: upscaleFactor, rendererTimes: $rendererTimes, drawLoopEnabled: $drawLoopEnabled)
                Text("Command Buffer \u{2300}t \(Int(rendererTimes.commandBufferAvg * 1000)) ms")
                    .font(.system(size: 36, weight: .semibold, design: .rounded))
                    .foregroundColor(.gray)
                    .padding(16)
            }
            HStack {
                HStack(spacing: 32) {
                    Button {
                        control = .framesToRender
                        framesToRender += 1
                    } label: {
                        MoreFramesIcon(count: 1)
                    }
                    Button {
                        control = .framesToRender
                        framesToRender += 10
                    } label: {
                        MoreFramesIcon(count: 10)
                    }
                    Button {
                        control = .framesToRender
                        framesToRender += 100
                    } label: {
                        MoreFramesIcon(count: 100)
                    }
                }
                .padding(.trailing, 24)
                Button {
                    control = .lineUp
                    lineUp = .oneByOne
                } label: {
                    Image(systemName: "square")
                        .resizable()
                        .frame(width: 42, height: 42)
                }
                .disabled(lineUp == .oneByOne || drawLoopEnabled)
                Button {
                    control = .lineUp
                    lineUp = .twoByTwo
                } label: {
                    Image(systemName: "square.grid.2x2")
                        .resizable()
                        .frame(width: 42, height: 42)
                }
                .disabled(lineUp == .twoByTwo || drawLoopEnabled)
                Button {
                    control = .lineUp
                    lineUp = .threeByThree
                } label: {
                    Image(systemName: "square.grid.3x3")
                        .resizable()
                        .frame(width: 42, height: 42)
                }
                .disabled(lineUp == .threeByThree || drawLoopEnabled)
                HStack(spacing: 32) {
                    Button {
                        control = .upscaleFactor
                        let factor = upscaleFactor * 2.0
                        upscaleFactor = factor > 8 ? 1.0 : factor
                    } label: {
                        UpscalerImage()
                            .frame(width: 42, height: 42)
                    }
                    .disabled(drawLoopEnabled)
                }
                .padding(.leading, 24)
            }
            .padding(.bottom, 8)
        }
    }
}

struct MoreFramesIcon: View {
    var count: UInt

    var body: some View {
        HStack(spacing: 0) {
            Image(systemName: "play")
                .resizable()
                .frame(width: 24, height: 24)
            Text("|")
                .font(.system(size: 26, weight: .medium, design: .rounded))
                .offset(x: 0, y: -2.4)
            Text("\(count)")
                .font(.system(size: 20, weight: .medium, design: .rounded))
            Text("|")
                .font(.system(size: 26, weight: .medium, design: .rounded))
                .offset(x: 0, y: -2.4)
        }
    }
}

struct UpscalerImage: View {
    var body: some View {
        GeometryReader { geometry in
            let w = geometry.size.width
            let h = geometry.size.height
            ZStack(alignment: .bottomLeading) {
                Image(systemName: "square")
                    .resizable()
                Image(systemName: "square.fill")
                    .resizable()
                    .frame(width: w / 2.0, height: h / 2.0)
                Image(systemName: "arrow.up.right")
                    .resizable()
                    .frame(width: w / 2.0, height: h / 2.0)
                    .offset(x: w / 2.0 * 0.72, y: -h / 2.0 * 0.72)
            }
        }
    }
}
