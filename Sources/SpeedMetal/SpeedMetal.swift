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
    var device: MTLDevice

    func makeCoordinator() -> Renderer {
        let stage = Stage.hoistCornellBox(lineUp: lineUp, device: device)
        return Renderer(stage: stage, enabled: $drawLoopEnabled, times: $rendererTimes, device: device)
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
        control = .none // prevent last command running after Renderer updated Bindings
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

    private var device: MTLDevice!
    private var noMetal3: Bool

    init() {
        device   = MTLCreateSystemDefaultDevice()
        noMetal3 = !device.supportsFamily(.metal3)
    }

    var body: some Scene {
        WindowGroup {
            ZStack(alignment: .topLeading) {
                if noMetal3 {
                    NoMetal3Comforter()
                } else {
                    SMView(control: $control, lineUp: lineUp, framesToRender: $framesToRender, upscaleFactor: upscaleFactor, rendererTimes: $rendererTimes, drawLoopEnabled: $drawLoopEnabled, device: device)
                    HighlightRaycerOutput(upscaleFactor: upscaleFactor)
                    RendererTimesPanel(rendererTimes: rendererTimes)
                }
                SocialMediaPanel()
            }
            FlightControlPanel(control: $control, lineUp: $lineUp, framesToRender: $framesToRender, upscaleFactor: $upscaleFactor, drawLoopEnabled: drawLoopEnabled, noMetal3: noMetal3)
        }
    }
}

struct NoMetal3Comforter: View {
    @State var isPresented = true

    var body: some View {
        VStack {
            ZStack {
                Image("smview-ipad")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                if isPresented {
                    NoMetal3Clue(isPresented: $isPresented)
                }
            }
        }
        .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity)
        .background(.black)
    }
}

struct NoMetal3Clue: View {
    @Binding var isPresented: Bool

    var body: some View {
        VStack {
            Text("Dein Device unterstützt die neuen Features von Metal 3 leider nicht.")
                .frame(maxWidth: 400)
                .multilineTextAlignment(.center)
            Text("Du siehst einen Screenshot der Szene mit 100+ Frames. Der Upscaler hat das umrahmte Renderergebnis des Raytracers mit Faktor 2 auf Displayformat vergrößert.")
                .font(.system(size: 20, design: .rounded))
                .frame(maxWidth: 350)
                .padding(.top, 1)
                .padding(.bottom, 16)
            Button("OK") {
                isPresented = false
            }
                .padding()
                .foregroundColor(.gray)
                .background(Color.accentColor)
                .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .padding()
        .foregroundColor(.accentColor)
        .background(.black.opacity(0.82))
        .font(.system(.title, design: .rounded))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

struct HighlightRaycerOutput: View {
    var upscaleFactor: Float

    var body: some View {
        GeometryReader { dim in
            VStack(alignment: .leading) {
                let upscaleFactor = CGFloat(upscaleFactor)
                // inversely map upscale factor 2...8 to linewidth 8...2
                let lineWidth = 8 - upscaleFactor / 8 * 6
                Spacer()
                RoundedRectangle(cornerRadius: 8, style: .circular)
                    .stroke(Color.accentColor.opacity(upscaleFactor > 1 ? 1 : 0), lineWidth: lineWidth)
                    .offset(x: lineWidth / 2, y: -lineWidth / 2)
                    .frame(width: dim.size.width / upscaleFactor, height: dim.size.height / upscaleFactor)
            }
        }
    }
}

struct RendererTimesPanel: View {
    var rendererTimes: RendererTimes

    var body: some View {
        HStack {
            VStack(alignment: .leading) {
                Text("Ausführungszeiten (ms)")
                    .padding(.bottom, 2)
                    .fontWeight(.bold)
                Text("GPU (3 Command Buffer)")
                Text("Renderer.draw Funktion")
            }
            .padding(.trailing, 24)
            VStack {
                Text("\u{03a3}")
                    .padding(.bottom, 2)
                    .fontWeight(.bold)
                Text(String(format: "%d", Int(rendererTimes.commandBufferSum * 1000)))
                Text(String(format: "%d", Int(rendererTimes.drawFunctionSum * 1000)))
            }
            .padding(.trailing, 12)
            VStack {
                Text("\u{2300}")
                    .padding(.bottom, 2)
                    .fontWeight(.bold)
                Text("\(Int(rendererTimes.commandBufferAvg * 1000))")
                Text("\(Int(rendererTimes.drawFunctionAvg * 1000))")
            }
        }
        .font(.system(.headline, design: .monospaced, weight: .regular))
        .foregroundColor(.gray)
        .padding(24)
    }
}

struct MoreFramesIcon: View {
    var label: UInt

    var body: some View {
        HStack(spacing: 0) {
            Image(systemName: "play")
                .resizable()
                .frame(width: 24, height: 24)
            Text("|")
                .font(.system(size: 26, weight: .medium, design: .rounded))
                .offset(x: 0, y: -2.4)
            Text("\(label)")
                .font(.system(size: 20, weight: .medium, design: .rounded))
            Text("|")
                .font(.system(size: 26, weight: .medium, design: .rounded))
                .offset(x: 0, y: -2.4)
        }
    }
}

struct UpscalerIcon: View {
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

struct SocialMediaPanel: View {
    var body: some View {
        HStack( spacing: 12) {
            Spacer()
            Link(destination: URL(string: "https://www.heise.de/mac-and-i/")!) {
                Image("mac_and_i-logo")
                    .resizable()
                    .frame(width: 42, height: 42)
                    .clipShape(/*@START_MENU_TOKEN@*/Circle()/*@END_MENU_TOKEN@*/)
            }
            Link(destination: URL(string: "https://twitter.com/mac_and_i")!) {
                Image("twitter-logo")
                    .resizable()
                    .frame(width: 42, height: 42)
            }
            Link(destination: URL(string: "https://github.com/otabuzzman/SpeedMetal.git")!) {
                Image("github-mark-white")
                    .resizable()
                    .frame(width: 42, height: 42)
            }
        }
        .padding(24)
    }
}

struct FlightControlPanel: View {
    @Binding var control: SMViewControl
    @Binding var lineUp: LineUp
    @Binding var framesToRender: UInt32
    @Binding var upscaleFactor: Float
    var drawLoopEnabled: Bool
    var noMetal3: Bool

    var body: some View {
        HStack {
            HStack(spacing: 32) {
                Button {
                    control = .framesToRender
                    framesToRender += 1
                } label: {
                    MoreFramesIcon(label: 1)
                }
                Button {
                    control = .framesToRender
                    framesToRender += 10
                } label: {
                    MoreFramesIcon(label: 10)
                }
                Button {
                    control = .framesToRender
                    framesToRender += 100
                } label: {
                    MoreFramesIcon(label: 100)
                }
            }
            .padding(.trailing, 24)
            Button {
                control = .lineUp
                lineUp  = .oneByOne
            } label: {
                Image(systemName: "square")
                    .resizable()
                    .frame(width: 42, height: 42)
            }
            .disabled(lineUp == .oneByOne || drawLoopEnabled)
            Button {
                control = .lineUp
                lineUp  = .twoByTwo
            } label: {
                Image(systemName: "square.grid.2x2")
                    .resizable()
                    .frame(width: 42, height: 42)
            }
            .disabled(lineUp == .twoByTwo || drawLoopEnabled)
            Button {
                control = .lineUp
                lineUp  = .threeByThree
            } label: {
                Image(systemName: "square.grid.3x3")
                    .resizable()
                    .frame(width: 42, height: 42)
            }
            .disabled(lineUp == .threeByThree || drawLoopEnabled)
            HStack(spacing: 32) {
                Button {
                    control = .upscaleFactor
                    let factor    = upscaleFactor * 2.0
                    upscaleFactor = factor > 8 ? 1.0 : factor
                } label: {
                    UpscalerIcon()
                        .frame(width: 42, height: 42)
                }
                .disabled(drawLoopEnabled)
            }
            .padding(.leading, 24)
        }
        .padding(.bottom, 8)
        .disabled(noMetal3)
    }
}
