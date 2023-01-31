import MetalKit
import MetalFX
import SwiftUI

class SMViewControl: ObservableObject {
    static let shared = SMViewControl()
    private init() {}

    enum SMViewCommand {
        case none
        case lineUp
        case framesToRender
        case upscaleFactor
    }

    @Published var control = SMViewCommand.none
    @Published var lineUp  = LineUp.threeByThree
    @Published var framesToRender: UInt32 = 1
    @Published var upscaleFactor: Float   = 1.0
}

struct SMView: UIViewRepresentable {
    @EnvironmentObject var smViewControl: SMViewControl

    func makeCoordinator() -> Renderer {
        let device = MTLCreateSystemDefaultDevice()!
        let stage  = Stage.hoistCornellBox(lineUp: smViewControl.lineUp, device: device)
        return Renderer(stage: stage, device: device)
    }

    func makeUIView(context: Context) -> MTKView {
        let view = MTKView(frame: .zero, device: context.coordinator.device)
        view.backgroundColor  = .black
        view.colorPixelFormat = .rgba16Float
        view.delegate         = context.coordinator
        view.preferredFramesPerSecond = 10
        return view
    }

    func updateUIView(_ view: MTKView, context: Context) {
        switch smViewControl.control {
        case .none:
            return
        case .lineUp:
            let stage = Stage.hoistCornellBox(lineUp: smViewControl.lineUp, device: view.device!)
            context.coordinator.framesToRender = 1
            context.coordinator.stage          = stage
            smViewControl.framesToRender = 1
        case .framesToRender:
            context.coordinator.framesToRender = smViewControl.framesToRender
        case .upscaleFactor:
            context.coordinator.framesToRender = 1
            context.coordinator.upscaleFactor  = smViewControl.upscaleFactor
            smViewControl.framesToRender = 1
        }
        smViewControl.control = .none // prevent last command running after Renderer updated Bindings
        view.isPaused = false
    }
}

struct ContentView: View {
    @StateObject var rendererControl = RendererControl.shared
    @StateObject var smViewControl   = SMViewControl.shared

    @State private var isPortrait = UIScreen.isPortrait

    private var noMetal3   = true
    private var noUpscaler = false

    init() {
        // should work safely on modern devices
        // and in simulator from Xcode 11 onwards
        let device = MTLCreateSystemDefaultDevice()!
        noMetal3   = !device.supportsFamily(.metal3)
        noUpscaler = !MTLFXSpatialScalerDescriptor.supportsDevice(device)
    }

    var body: some View {
        ZStack {
            AdaptiveContent(title: "SpeedMetal", isPortrait: isPortrait, noMetal3: noMetal3)
                .environmentObject(smViewControl)
                .environmentObject(rendererControl)
                .background(.black)
                .onRotate(isPortrait: $isPortrait) { _ in
                    // advance single frame to force redraw
                    smViewControl.control = .framesToRender
                    smViewControl.framesToRender += 1
                }

            if rendererControl.drawLoopEnabled {
                SMBusy()
                    .transition(.opacity.animation(Animation.easeIn(duration: 1)))
            }
        }

        FlightControlPanel(smViewControl: smViewControl, drawLoopEnabled: rendererControl.drawLoopEnabled, noUpscaler: noUpscaler)
            .padding()
            .disabled(noMetal3)
    }
}

struct AdaptiveContent: View {
    var title: String
    var isPortrait: Bool
    var noMetal3: Bool

    private var sharedContent: some View {
        if noMetal3 {
            return NoMetal3Comfort()
        } else {
            return ZStack {
                SMView()
                HighlightRaycerOutput()
            }
        }
    }

    var body: some View {
        if isPortrait {
            VStack {
                SocialMediaHeadline(title: title)
                    .padding()
                RendererTimesPanel()
                    .padding()

                sharedContent
            }
        } else {
            HStack {
                VStack {
                    Headline(title: title)
                        .padding()
                    RendererTimesPanel()
                        .padding()
                    Spacer()
                }

                sharedContent

                VStack {
                    SocialMediaPanel()
                        .padding()
                    Spacer()
                }
            }
        }
    }
}

extension UIScreen {
    static var isLandscape: Bool {
        get { Self.main.bounds.aspectRatio > 1 }
    }

    static var isPortrait: Bool {
        get { !isLandscape }
    }
}

extension CGRect {
    var aspectRatio: CGFloat {
        get { width / height }
    }
}

struct OnRotate: ViewModifier {
    @Binding var isPortrait: Bool
    let action: (UIDeviceOrientation) -> Void

    func body(content: Content) -> some View {
        content
            .onReceive(NotificationCenter.default.publisher(for: UIDevice.orientationDidChangeNotification)) { orientation in
                // https://stackoverflow.com/a/65586833/9172095
                // UIDevice.orientation not save on app launch
                let scenes = UIApplication.shared.connectedScenes
                let windowScene = scenes.first as? UIWindowScene

                guard
                    let isPortrait = windowScene?.interfaceOrientation.isPortrait
                else { return }

                // interface orientation not affected when rotated to flat
                if self.isPortrait == isPortrait { return }

                self.isPortrait = isPortrait

                action(UIDevice.current.orientation)
            }
    }
}

extension View {
    func onRotate(isPortrait: Binding<Bool>, perform action: @escaping (UIDeviceOrientation) -> Void) -> some View {
        self.modifier(OnRotate(isPortrait: isPortrait, action: action))
    }
}

struct SMBusy: View {
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12)
                .foregroundColor(Color(.systemGray5))
            ProgressView()
                .progressViewStyle(CircularProgressViewStyle(tint: .accentColor))
        }
        .frame(width: 64, height: 64)
    }
}

struct SocialMediaHeadline: View {
    var title: String

    var body: some View {
        HStack {
            Headline(title: title)
            Spacer()
            SocialMediaPanel()
        }
    }
}

struct Headline: View {
    var title: String

    @Environment(\.horizontalSizeClass) private var sizeClass
    private var isRegular: Bool {
        sizeClass == .regular
    }

    var body: some View {
        Text(title)
            .font(.system(isRegular ? .largeTitle : .title, design: .rounded, weight: .semibold))
            .foregroundColor(.gray)
    }
}

struct SocialMediaPanel: View {
    @Environment(\.horizontalSizeClass) private var sizeClass
    private var isRegular: Bool {
        sizeClass == .regular
    }

    var body: some View {
        HStack {
            let iconSize: CGFloat = isRegular ? 44 : 36
            Group {
                Link(destination: URL(string: "https://www.heise.de/mac-and-i/")!) {
                    Image("mac_and_i-logo")
                        .resizable()
                        .clipShape(Circle())
                }
                Link(destination: URL(string: "https://twitter.com/mac_and_i")!) {
                    Image("twitter-logo")
                        .resizable()
                }
                Link(destination: URL(string: "https://github.com/otabuzzman/SpeedMetal.git")!) {
                    Image("github-mark-white")
                        .resizable()
                }
            }
            .frame(width: iconSize, height: iconSize)
        }
    }
}

struct RendererTimesPanel: View {
    @EnvironmentObject var rendererControl: RendererControl

    @Environment(\.horizontalSizeClass) private var sizeClass
    private var isRegular: Bool {
        sizeClass == .regular
    }

    var body: some View {
        HStack {
            VStack(alignment: .leading) {
                Text("Ausführungszeiten (ms)  ")
                    .padding(.bottom, 2)
                    .fontWeight(.bold)
                Text("GPU (3 Command Buffer) :")
                Text("Renderer.draw Funktion :")
            }
            VStack {
                Text("\u{03a3}")
                    .padding(.bottom, 2)
                    .fontWeight(.bold)
                Text(String(format: "%6d", Int(rendererControl.commandBufferSum * 1000)))
                Text(String(format: "%6d", Int(rendererControl.drawFunctionSum * 1000)))
            }
            VStack {
                Text("\u{2300}")
                    .padding(.bottom, 2)
                    .fontWeight(.bold)
                Text(String(format: "%6d", Int(rendererControl.commandBufferAvg * 1000)))
                Text(String(format: "%6d", Int(rendererControl.drawFunctionSum * 1000)))
            }
        }
        .font(.system(isRegular ? .title3 : .headline, design: .monospaced, weight: .regular))
        .foregroundColor(.gray)
    }
}

struct NoMetal3Comfort: View {
    @State private var isPresented = true

    var body: some View {
        VStack {
            Image("smview-regular")
                .resizable()
                .aspectRatio(contentMode: .fit)
        }
        .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity)
        .alert("Dein Device unterstützt die neuen Features von Metal 3 leider nicht.", isPresented: $isPresented) {} message: {
            Text("Den Screenshot im Hintergrund hat die App auf einem iPad Pro 2022 gerendert und dabei den umrahmten Output des Raytracers mit dem Upscaler um Faktor 2 vergrößert.")
        }
    }
}

struct HighlightRaycerOutput: View {
    @EnvironmentObject var smViewControl: SMViewControl

    var body: some View {
        GeometryReader { dim in
            VStack(alignment: .leading) {
                let upscaleFactor = CGFloat(smViewControl.upscaleFactor)
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

struct FlightControlPanel: View {
    var smViewControl: SMViewControl
    var drawLoopEnabled: Bool
    var noUpscaler: Bool

    @Environment(\.horizontalSizeClass) private var sizeClass
    private var isRegular: Bool {
        sizeClass == .regular
    }

    var body: some View {
        HStack {
            let iconSize: CGFloat = isRegular ? 44 : 36
            HStack {
                Button {
                    smViewControl.control = .framesToRender
                    smViewControl.framesToRender += 5
                } label: {
                    Image(systemName: "goforward.5")
                        .resizable()
                        .frame(width: iconSize, height: iconSize)
                }
                Button {
                    smViewControl.control = .framesToRender
                    smViewControl.framesToRender += 45
                } label: {
                    Image(systemName: "goforward.45")
                        .resizable()
                        .frame(width: iconSize, height: iconSize)
                }
                Button {
                    smViewControl.control = .framesToRender
                    smViewControl.framesToRender += 90
                } label: {
                    Image(systemName: "goforward.90")
                        .resizable()
                        .frame(width: iconSize, height: iconSize)
                }
            }
            Button {
                smViewControl.control = .lineUp
                smViewControl.lineUp  = .oneByOne
            } label: {
                Image(systemName: "square")
                    .resizable()
                    .frame(width: iconSize, height: iconSize)
            }
            .disabled(smViewControl.lineUp == .oneByOne || drawLoopEnabled)
            Button {
                smViewControl.control = .lineUp
                smViewControl.lineUp  = .twoByTwo
            } label: {
                Image(systemName: "square.grid.2x2")
                    .resizable()
                    .frame(width: iconSize, height: iconSize)
            }
            .disabled(smViewControl.lineUp == .twoByTwo || drawLoopEnabled)
            Button {
                smViewControl.control = .lineUp
                smViewControl.lineUp  = .threeByThree
            } label: {
                Image(systemName: "square.grid.3x3")
                    .resizable()
                    .frame(width: iconSize, height: iconSize)
            }
            .disabled(smViewControl.lineUp == .threeByThree || drawLoopEnabled)
            HStack {
                Button {
                    smViewControl.control = .upscaleFactor
                    let factor = smViewControl.upscaleFactor * 2.0
                    smViewControl.upscaleFactor = factor > 8 ? 1.0 : factor
                } label: {
                    UpscalerIcon()
                        .frame(width: iconSize, height: iconSize)
                }
                .disabled(noUpscaler || drawLoopEnabled)
            }
        }
    }
}

struct UpscalerIcon: View {
    var body: some View {
        GeometryReader { dim in
            let w = dim.size.width
            let h = dim.size.height
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

@main
struct SpeedMetal: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
