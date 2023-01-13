import MetalKit
import SwiftUI

enum SMViewControl {
	case none
	case lineUp
	case framesToRender
}

struct SMView: UIViewRepresentable {
	var control: SMViewControl
    var lineUp: LineUp
    var framesToRender: UInt32
    
    init(_ control: SMViewControl, lineUp: LineUp, framesToRender: UInt32) {
		self.control        = control
        self.lineUp         = lineUp
        self.framesToRender = framesToRender
    }
    
    func makeCoordinator() -> Renderer {
        guard
            let device = MTLCreateSystemDefaultDevice(),
            device.supportsFamily(.metal3)
        else {
            fatalError("no Metal 3 capable GPU available")
        }
        let stage = Stage.hoistCornellBox(lineUp: lineUp, device: device)
        return Renderer(stage: stage, device: device)
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
			break
		case .lineUp:
			let stage = Stage.hoistCornellBox(lineUp: lineUp, device: view.device!)
			context.coordinator.stage = stage
		case .framesToRender:
			context.coordinator.framesToRender = framesToRender
		}
    }
}

@main
struct SpeedMetal: App {
	@State var control = SMViewControl.none
    @State var lineUp  = LineUp.threeByThree
    @State var framesToRender: UInt32 = 1

    var body: some Scene {
        WindowGroup {
            SMView(control, lineUp: lineUp, framesToRender: framesToRender)
            HStack {
                Button {
					control = .framesToRender
                    framesToRender += 1
                } label: {
                    Text("1x")
                        .font(.title2)
                }
                Button {
					control = .framesToRender
                    framesToRender += 10
                } label: {
                    Text("10x")
                        .font(.title2)
                }
                Button {
					control = .framesToRender
                    framesToRender += 100
                } label: {
                    Text("100x")
                        .font(.title2)
                }
                Button {
					control = .lineUp
                    lineUp = .oneByOne
                } label: {
                    Image(systemName: "square")
                        .resizable()
                        .frame(width: 42, height: 42)
                }
                .disabled(lineUp == .oneByOne)
                Button {
					control = .lineUp
                    lineUp = .twoByTwo
                } label: {
                    Image(systemName: "square.grid.2x2")
                        .resizable()
                        .frame(width: 42, height: 42)
                }
                .disabled(lineUp == .twoByTwo)
                Button {
					control = .lineUp
                    lineUp = .threeByThree
                } label: {
                    Image(systemName: "square.grid.3x3")
                        .resizable()
                        .frame(width: 42, height: 42)
                }
                .disabled(lineUp == .threeByThree)
            }
            .padding(.bottom, 8)
        }
    }
}
