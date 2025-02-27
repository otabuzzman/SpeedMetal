import MetalKit
import MetalFX
import SwiftUI

struct ErrorWrapper {
    var error: NSError
    var guidance: String
}

class ErrorHandler: ObservableObject {
    @Published var current: ErrorWrapper! { didSet { isError = true } }
    @Published var isError = false

    func record(_ error: NSError, _ guidance: String) {
        current = ErrorWrapper(error: error, guidance: guidance)
    }
}

class SMViewControl: ObservableObject {
    static let shared = SMViewControl()
    private init() {}

    enum SMViewCommand {
        case none
        case lineUp
        case framesToRender
        case upscaleFactor
        case harvestPipelines(URL)
    }

    @Published var control = SMViewCommand.none
    var lineUp  = LineUp.threeByThree
    var framesToRender: UInt32 = 1
    var upscaleFactor: Float   = 1.0
}

struct SMView: UIViewRepresentable {
    @EnvironmentObject var rendererControl: RendererControl
    @EnvironmentObject var smViewControl: SMViewControl
    @EnvironmentObject var errorHandler: ErrorHandler

    func makeCoordinator() -> Renderer? {
        let device = MTLCreateSystemDefaultDevice()!
        let stage  = Stage.hoistCornellBox(lineUp: smViewControl.lineUp, device: device)

        do {
            return try Renderer(stage: stage, device: device)
        } catch let error as NSError {
            errorHandler.record(error, "Die Ursache könnte ein vorübergehender Ressourcenmangel sein. Starte die App nochmal oder boote dein Device. Tippe im Display oben rechts auf GitHub und öffne einen Issue mit einer Fehlerbeschreibung, und wie es dazu kam.")
        }

        return nil
    }

    func makeUIView(context: Context) -> MTKView {
        let view = MTKView(frame: .zero, device: context.coordinator?.device)
        view.backgroundColor  = .black
        view.colorPixelFormat = .rgba16Float
        view.delegate         = context.coordinator

        return view
    }

    func updateUIView(_ view: MTKView, context: Context) {
        guard
            let renderer = context.coordinator
        else { return }

        switch smViewControl.control {
        case .none:
            return
        case .lineUp:
            let stage = Stage.hoistCornellBox(lineUp: smViewControl.lineUp, device: view.device!)
            renderer.framesToRender = 1
            renderer.stage          = stage
            smViewControl.framesToRender = 1
        case .framesToRender:
            renderer.framesToRender = smViewControl.framesToRender
        case .upscaleFactor:
            renderer.framesToRender = 1
            renderer.upscaleFactor  = smViewControl.upscaleFactor
            smViewControl.framesToRender = 1
        case .harvestPipelines(let folder):
            guard
                folder.startAccessingSecurityScopedResource()
            else { return }
            defer { folder.stopAccessingSecurityScopedResource() }

            do {
                let libFile = folder.appendingPathComponent("speedmetal.metallib")
                let descriptor = MTLBinaryArchiveDescriptor()
                let archive = try renderer.device.makeBinaryArchive(descriptor: descriptor)
                try archive.addRenderPipelineFunctions(descriptor: renderer.shaderDescriptor)
                try archive.addComputePipelineFunctions(descriptor: renderer.raycerDescriptor)
                try archive.serialize(to: libFile)
            } catch let error as NSError {
                errorHandler.record(error, "Tippe im Display oben rechts auf GitHub und öffne einen Issue mit einer Fehlerbeschreibung, und wie es dazu kam.")
            }

            return
        }
        smViewControl.control = .none // prevent last command running after Renderer updated Bindings
        rendererControl.drawLoopEnabled = true
        view.isPaused                   = false
    }
}

struct ContentView: View {
    @StateObject var rendererControl = RendererControl.shared
    @StateObject var smViewControl   = SMViewControl.shared
    @StateObject var errorHandler    = ErrorHandler()

    @State private var isPortrait = UIScreen.isPortrait

    @Environment(\.verticalSizeClass) private var verticalSizeClass
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    private var isCompact: Bool {
        verticalSizeClass == .compact || horizontalSizeClass == .compact
    }

    private var noMetal3   = true
    private var noUpscaler = true

    init() {
        // should work safely on modern devices
        // and in simulator from Xcode 11 onwards
        let device = MTLCreateSystemDefaultDevice()!
        noMetal3 = !device.supportsFamily(.metal3)
        noUpscaler = !MTLFXSpatialScalerDescriptor.supportsDevice(device)
    }

    var body: some View {
        ZStack {
            AdaptiveContent(title: "SpeedMetal", isPortrait: isPortrait, noMetal3: noMetal3)
                .environmentObject(smViewControl)
                .environmentObject(rendererControl)
                .environmentObject(errorHandler)
                .background(.black)
                .onRotate(isPortrait: $isPortrait) { _ in
                    smViewControl.upscaleFactor = 1.0
                    smViewControl.control = .upscaleFactor
                }

            if rendererControl.drawLoopEnabled && !noMetal3 {
                SMBusy()
                    .transition(.opacity.animation(Animation.easeIn(duration: 1)))
            }
        }

        FlightControlPanel(smViewControl: smViewControl, drawLoopEnabled: rendererControl.drawLoopEnabled, noUpscaler: noUpscaler)
            .padding(isCompact ? .top : .vertical)
            .disabled(noMetal3 || errorHandler.isError)
    }
}

struct AdaptiveContent: View {
    var title: String
    var isPortrait: Bool
    var noMetal3: Bool

    @EnvironmentObject var errorHandler: ErrorHandler

    @ViewBuilder private var smView: some View {
        ZStack {
            SMView()
            HighlightRaycerOutput()
        }
        .substitute(if: noMetal3) { _ in
            NoMetal3Comfort()
        }
        .substitute(if: errorHandler.isError) { _ in
            SMViewError(errorHandler: errorHandler)
        }
    }

    var body: some View {
        if isPortrait {
            VStack {
                SocialMediaHeadline(title: title)
                    .padding()
                RendererTimesPanel()
                    .padding()

                smView
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

                smView

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
    func onRotate(isPortrait: Binding<Bool>, action: @escaping (UIDeviceOrientation) -> Void) -> some View {
        self.modifier(OnRotate(isPortrait: isPortrait, action: action))
    }

    @ViewBuilder func substitute(if condition: Bool, content: (Self) -> some View) -> some View {
        if condition {
            content(self)
        } else {
            self
        }
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

    @Environment(\.verticalSizeClass) private var verticalSizeClass
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    private var isRegular: Bool {
        verticalSizeClass == .regular && horizontalSizeClass == .regular
    }

    var body: some View {
        HStack {
            VStack(alignment: .leading) {
                Text(isRegular ? "Ausführungszeiten (ms)  " : "ms    ")
                    .padding(.bottom, 2)
                    .fontWeight(.bold)
                Text(isRegular ? "GPU (3 Command Buffer) :" : "GPU  :")
                Text(isRegular ? "Renderer.draw Funktion :" : "draw :")
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

struct SMViewError: View {
    var errorHandler: ErrorHandler

    @State private var isPresented = true

    var body: some View {
        VStack {
            Image("smview-broken")
                .resizable()
                .aspectRatio(contentMode: .fit)
        }
        .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity)
        .alert("Es gab einen Fehler : \(errorHandler.current.error.localizedDescription)", isPresented: $isPresented) {} message: {
            Text("\(errorHandler.current.error)\n***\n\(errorHandler.current.guidance)")
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

    @State private var isPresented = false
    
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
            Button {
                isPresented = true
            } label: {
                Image(systemName: "square.and.arrow.down.on.square")
                    .resizable()
                    .frame(width: iconSize, height: iconSize)
            }
            .disabled(drawLoopEnabled)
        }
        .sheet(isPresented: $isPresented) {
            FolderPicker() { result in
                switch result {
                case .success(let folder):
                    smViewControl.control = .harvestPipelines(folder)
                default:
                    break
                }
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

enum FolderPickerError: Error {
    case canceled
    case unknown
}

struct FolderPicker: UIViewControllerRepresentable {
    var completion: ((Result<URL, FolderPickerError>) -> Void)?
    
    func makeUIViewController(context: UIViewControllerRepresentableContext<FolderPicker>) -> UIDocumentPickerViewController {
        let controller = UIDocumentPickerViewController(forOpeningContentTypes: [.folder])
        controller.delegate = context.coordinator
        controller.allowsMultipleSelection = false
        
        return controller
    }
    
    func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: UIViewControllerRepresentableContext<FolderPicker>) {
    }
    
    func makeCoordinator() -> FolderPickerCoordinator {
        FolderPickerCoordinator(completion)
    }
}

class FolderPickerCoordinator: NSObject, UINavigationControllerDelegate {
    var completion: ((Result<URL, FolderPickerError>) -> Void)?
    
    init(_ completion: ((Result<URL, FolderPickerError>) -> Void)?) {
        self.completion = completion
    }
}

extension FolderPickerCoordinator: UIDocumentPickerDelegate {
    func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
        completion?(.failure(.canceled))
    }
    
    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        if let folder = urls.first {
            completion?(.success(folder))
        } else {
            completion?(.failure(.unknown))
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
