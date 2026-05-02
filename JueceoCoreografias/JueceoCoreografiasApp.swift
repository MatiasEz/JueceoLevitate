import SwiftUI

@main
struct JueceoCoreografiasApp: App {
    @StateObject private var store = JudgingStore()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(store)
        }
    }
}
