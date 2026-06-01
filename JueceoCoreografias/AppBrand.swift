import Foundation
import SwiftUI
import JueceoCore

#if canImport(UIKit)
import UIKit
#endif

enum AppBrand {
    static let competition: CompetitionBranding = {
        CompetitionBranding.brand(id: Bundle.main.object(forInfoDictionaryKey: "APP_BRAND_ID") as? String) ?? .levitate
    }()
}

extension CompetitionBrandColor {
    var swiftUIColor: Color {
        Color(red: red, green: green, blue: blue, opacity: alpha)
    }

    #if canImport(UIKit)
    var uiColor: UIColor {
        UIColor(red: CGFloat(red), green: CGFloat(green), blue: CGFloat(blue), alpha: CGFloat(alpha))
    }
    #endif
}

extension CompetitionAdaptiveColor {
    var swiftUIColor: Color {
        #if canImport(UIKit)
        Color(UIColor { traits in
            let resolved = traits.userInterfaceStyle == .dark ? dark : light
            return resolved.uiColor
        })
        #else
        light.swiftUIColor
        #endif
    }

    #if canImport(UIKit)
    var lightUIColor: UIColor {
        light.uiColor
    }

    var dynamicUIColor: UIColor {
        UIColor { traits in
            let resolved = traits.userInterfaceStyle == .dark ? dark : light
            return resolved.uiColor
        }
    }
    #endif
}
