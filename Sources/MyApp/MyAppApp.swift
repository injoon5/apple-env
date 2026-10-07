import SwiftUI

@main
struct MyAppApp: App {
    @State private var store = TodoStore()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(store)
                .tint(Color("AccentColor", bundle: .assets))
        }
    }
}
