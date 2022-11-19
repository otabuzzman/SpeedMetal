import SwiftUI

struct ContentView: View {
    var body: some View {
        VStack {
            Image(systemName: "dumbbell")
                .imageScale(.large)
                .foregroundColor(.accentColor)
            Text("Heavy Metal")
        }
    }
}

@main
struct HeavyMetal: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
