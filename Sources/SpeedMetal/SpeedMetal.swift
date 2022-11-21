import SwiftUI

struct ContentView: View {
    var body: some View {
        VStack {
            Image(systemName: "dumbbell")
                .imageScale(.large)
                .foregroundColor(.accentColor)
            Text("Speed Metal")
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

