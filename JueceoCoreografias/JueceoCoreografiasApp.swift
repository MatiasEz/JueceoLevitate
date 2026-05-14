import SwiftUI
import UIKit

@main
struct JueceoCoreografiasApp: App {
    @StateObject private var store = JudgingStore()

    var body: some Scene {
        WindowGroup {
            if UIDevice.current.userInterfaceIdiom == .phone {
                PhoneContentView()
                    .environmentObject(store)
            } else {
                ContentView()
                    .environmentObject(store)
            }
        }
    }
}
