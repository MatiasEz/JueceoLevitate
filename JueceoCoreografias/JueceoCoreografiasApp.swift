import SwiftUI

#if canImport(UIKit)
import UIKit
#endif

@main
struct JueceoCoreografiasApp: App {
    @StateObject private var store: JudgingStore

    init() {
        #if targetEnvironment(macCatalyst)
        Self.resetMacCatalystDefaults()
        #endif
        _store = StateObject(wrappedValue: JudgingStore())
    }

    var body: some Scene {
        WindowGroup {
            rootView
                .environmentObject(store)
                .onOpenURL { url in
                    GoogleOAuthCallbackCoordinator.shared.handle(url)
                }
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

    #if targetEnvironment(macCatalyst)
    private static func resetMacCatalystDefaults() {
        guard let bundleIdentifier = Bundle.main.bundleIdentifier else { return }
        UserDefaults.standard.removePersistentDomain(forName: bundleIdentifier)
        UserDefaults.standard.synchronize()
    }
    #endif
}
