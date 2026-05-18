import SwiftUI

#if canImport(UIKit)
import UIKit
#endif

@main
struct JueceoCoreografiasApp: App {
    @StateObject private var store = JudgingStore()

    var body: some Scene {
        WindowGroup {
            rootView
                .environmentObject(store)
        }
    }

    @ViewBuilder
    private var rootView: some View {
        #if targetEnvironment(macCatalyst)
        ContentView()
        #elseif canImport(UIKit)
        if UIDevice.current.userInterfaceIdiom == .phone {
            PhoneContentView()
        } else {
            ContentView()
        }
        #else
        ContentView()
        #endif
    }
}
