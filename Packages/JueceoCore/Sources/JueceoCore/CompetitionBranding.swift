import Foundation

public struct CompetitionBrandColor: Codable, Hashable, Sendable {
    public let red: Double
    public let green: Double
    public let blue: Double
    public let alpha: Double

    public init(red: Double, green: Double, blue: Double, alpha: Double = 1) {
        self.red = red
        self.green = green
        self.blue = blue
        self.alpha = alpha
    }
}

public struct CompetitionAdaptiveColor: Codable, Hashable, Sendable {
    public let light: CompetitionBrandColor
    public let dark: CompetitionBrandColor

    public init(light: CompetitionBrandColor, dark: CompetitionBrandColor) {
        self.light = light
        self.dark = dark
    }
}

public struct CompetitionColorPalette: Codable, Hashable, Sendable {
    public let primary: CompetitionBrandColor
    public let secondary: CompetitionBrandColor
    public let accentTint: CompetitionAdaptiveColor
    public let dark: CompetitionBrandColor
    public let darkPanel: CompetitionBrandColor
    public let darkPanel2: CompetitionBrandColor
    public let ink: CompetitionAdaptiveColor
    public let muted: CompetitionAdaptiveColor
    public let paper: CompetitionAdaptiveColor
    public let surface: CompetitionAdaptiveColor
    public let solidSurface: CompetitionAdaptiveColor
    public let elevatedSurface: CompetitionAdaptiveColor
    public let sidebarSurface: CompetitionAdaptiveColor
    public let softFill: CompetitionAdaptiveColor
    public let cardStroke: CompetitionAdaptiveColor
    public let line: CompetitionAdaptiveColor
    public let silverPodium: CompetitionAdaptiveColor
    public let bronzePodium: CompetitionAdaptiveColor

    public init(
        primary: CompetitionBrandColor,
        secondary: CompetitionBrandColor,
        accentTint: CompetitionAdaptiveColor,
        dark: CompetitionBrandColor,
        darkPanel: CompetitionBrandColor,
        darkPanel2: CompetitionBrandColor,
        ink: CompetitionAdaptiveColor,
        muted: CompetitionAdaptiveColor,
        paper: CompetitionAdaptiveColor,
        surface: CompetitionAdaptiveColor,
        solidSurface: CompetitionAdaptiveColor,
        elevatedSurface: CompetitionAdaptiveColor,
        sidebarSurface: CompetitionAdaptiveColor,
        softFill: CompetitionAdaptiveColor,
        cardStroke: CompetitionAdaptiveColor,
        line: CompetitionAdaptiveColor,
        silverPodium: CompetitionAdaptiveColor,
        bronzePodium: CompetitionAdaptiveColor
    ) {
        self.primary = primary
        self.secondary = secondary
        self.accentTint = accentTint
        self.dark = dark
        self.darkPanel = darkPanel
        self.darkPanel2 = darkPanel2
        self.ink = ink
        self.muted = muted
        self.paper = paper
        self.surface = surface
        self.solidSurface = solidSurface
        self.elevatedSurface = elevatedSurface
        self.sidebarSurface = sidebarSurface
        self.softFill = softFill
        self.cardStroke = cardStroke
        self.line = line
        self.silverPodium = silverPodium
        self.bronzePodium = bronzePodium
    }
}

public extension CompetitionBrandColor {
    static func rgb(_ red: Double, _ green: Double, _ blue: Double, alpha: Double = 1) -> Self {
        .init(red: red, green: green, blue: blue, alpha: alpha)
    }
}

public extension CompetitionAdaptiveColor {
    static func adaptive(light: CompetitionBrandColor, dark: CompetitionBrandColor) -> Self {
        .init(light: light, dark: dark)
    }
}

public extension CompetitionColorPalette {
    static let levitate = CompetitionColorPalette(
        primary: .rgb(0.93, 0.16, 0.45),
        secondary: .rgb(1.0, 0.25, 0.56),
        accentTint: .adaptive(light: .rgb(1.0, 0.90, 0.94), dark: .rgb(0.24, 0.08, 0.15)),
        dark: .rgb(0.045, 0.055, 0.075),
        darkPanel: .rgb(0.085, 0.10, 0.13),
        darkPanel2: .rgb(0.115, 0.13, 0.16),
        ink: .adaptive(light: .rgb(0.12, 0.13, 0.17), dark: .rgb(0.94, 0.95, 0.98)),
        muted: .adaptive(light: .rgb(0.48, 0.49, 0.56), dark: .rgb(0.64, 0.66, 0.73)),
        paper: .adaptive(light: .rgb(0.985, 0.985, 0.99), dark: .rgb(0.045, 0.055, 0.075)),
        surface: .adaptive(light: .rgb(1.0, 1.0, 1.0, alpha: 0.74), dark: .rgb(0.115, 0.13, 0.16, alpha: 0.78)),
        solidSurface: .adaptive(light: .rgb(1.0, 1.0, 1.0), dark: .rgb(0.115, 0.13, 0.16)),
        elevatedSurface: .adaptive(light: .rgb(1.0, 1.0, 1.0, alpha: 0.88), dark: .rgb(0.14, 0.155, 0.19, alpha: 0.92)),
        sidebarSurface: .adaptive(light: .rgb(1.0, 1.0, 1.0, alpha: 0.76), dark: .rgb(1.0, 1.0, 1.0, alpha: 0.035)),
        softFill: .adaptive(light: .rgb(0.0, 0.0, 0.0, alpha: 0.045), dark: .rgb(1.0, 1.0, 1.0, alpha: 0.075)),
        cardStroke: .adaptive(light: .rgb(1.0, 1.0, 1.0, alpha: 0.86), dark: .rgb(1.0, 1.0, 1.0, alpha: 0.08)),
        line: .adaptive(light: .rgb(0.0, 0.0, 0.0, alpha: 0.07), dark: .rgb(1.0, 1.0, 1.0, alpha: 0.08)),
        silverPodium: .adaptive(light: .rgb(0.93, 0.93, 0.95), dark: .rgb(0.15, 0.16, 0.19)),
        bronzePodium: .adaptive(light: .rgb(0.98, 0.90, 0.84), dark: .rgb(0.20, 0.15, 0.12))
    )

    static let auroraCircuit = CompetitionColorPalette(
        primary: .rgb(0.0, 0.58, 0.69),
        secondary: .rgb(0.21, 0.86, 0.68),
        accentTint: .adaptive(light: .rgb(0.83, 0.97, 0.95), dark: .rgb(0.03, 0.18, 0.19)),
        dark: .rgb(0.018, 0.065, 0.085),
        darkPanel: .rgb(0.035, 0.105, 0.13),
        darkPanel2: .rgb(0.055, 0.145, 0.17),
        ink: .adaptive(light: .rgb(0.035, 0.14, 0.16), dark: .rgb(0.92, 0.99, 0.98)),
        muted: .adaptive(light: .rgb(0.38, 0.50, 0.53), dark: .rgb(0.62, 0.75, 0.76)),
        paper: .adaptive(light: .rgb(0.965, 0.985, 0.982), dark: .rgb(0.018, 0.065, 0.085)),
        surface: .adaptive(light: .rgb(0.99, 1.0, 0.995, alpha: 0.78), dark: .rgb(0.055, 0.145, 0.17, alpha: 0.78)),
        solidSurface: .adaptive(light: .rgb(1.0, 1.0, 0.995), dark: .rgb(0.055, 0.145, 0.17)),
        elevatedSurface: .adaptive(light: .rgb(1.0, 1.0, 0.995, alpha: 0.90), dark: .rgb(0.075, 0.18, 0.205, alpha: 0.92)),
        sidebarSurface: .adaptive(light: .rgb(0.99, 1.0, 0.995, alpha: 0.78), dark: .rgb(0.67, 1.0, 0.92, alpha: 0.04)),
        softFill: .adaptive(light: .rgb(0.0, 0.34, 0.38, alpha: 0.055), dark: .rgb(0.66, 1.0, 0.91, alpha: 0.085)),
        cardStroke: .adaptive(light: .rgb(0.65, 0.91, 0.90, alpha: 0.50), dark: .rgb(0.64, 1.0, 0.91, alpha: 0.12)),
        line: .adaptive(light: .rgb(0.0, 0.38, 0.44, alpha: 0.095), dark: .rgb(0.72, 1.0, 0.94, alpha: 0.10)),
        silverPodium: .adaptive(light: .rgb(0.88, 0.95, 0.95), dark: .rgb(0.12, 0.20, 0.22)),
        bronzePodium: .adaptive(light: .rgb(0.92, 0.91, 0.82), dark: .rgb(0.17, 0.18, 0.12))
    )

    static let prismaOpen = CompetitionColorPalette(
        primary: .rgb(0.46, 0.25, 0.93),
        secondary: .rgb(1.0, 0.62, 0.13),
        accentTint: .adaptive(light: .rgb(0.94, 0.90, 1.0), dark: .rgb(0.15, 0.09, 0.27)),
        dark: .rgb(0.055, 0.045, 0.11),
        darkPanel: .rgb(0.095, 0.075, 0.17),
        darkPanel2: .rgb(0.135, 0.095, 0.21),
        ink: .adaptive(light: .rgb(0.13, 0.09, 0.22), dark: .rgb(0.96, 0.94, 1.0)),
        muted: .adaptive(light: .rgb(0.50, 0.44, 0.61), dark: .rgb(0.70, 0.66, 0.78)),
        paper: .adaptive(light: .rgb(0.985, 0.975, 0.995), dark: .rgb(0.055, 0.045, 0.11)),
        surface: .adaptive(light: .rgb(1.0, 1.0, 1.0, alpha: 0.76), dark: .rgb(0.135, 0.095, 0.21, alpha: 0.80)),
        solidSurface: .adaptive(light: .rgb(1.0, 1.0, 1.0), dark: .rgb(0.135, 0.095, 0.21)),
        elevatedSurface: .adaptive(light: .rgb(1.0, 1.0, 1.0, alpha: 0.90), dark: .rgb(0.17, 0.12, 0.25, alpha: 0.92)),
        sidebarSurface: .adaptive(light: .rgb(1.0, 0.995, 0.985, alpha: 0.78), dark: .rgb(1.0, 0.78, 0.36, alpha: 0.045)),
        softFill: .adaptive(light: .rgb(0.31, 0.14, 0.75, alpha: 0.055), dark: .rgb(1.0, 0.76, 0.32, alpha: 0.085)),
        cardStroke: .adaptive(light: .rgb(0.82, 0.72, 1.0, alpha: 0.52), dark: .rgb(1.0, 0.76, 0.32, alpha: 0.13)),
        line: .adaptive(light: .rgb(0.31, 0.14, 0.75, alpha: 0.09), dark: .rgb(1.0, 0.76, 0.32, alpha: 0.10)),
        silverPodium: .adaptive(light: .rgb(0.92, 0.90, 0.96), dark: .rgb(0.17, 0.14, 0.22)),
        bronzePodium: .adaptive(light: .rgb(1.0, 0.90, 0.76), dark: .rgb(0.24, 0.16, 0.08))
    )
}

public struct CompetitionBranding: Codable, Hashable, Sendable {
    public let id: String
    public let displayName: String
    public let logoAssetName: String
    public let heroFallbackAssetName: String
    public let driveRootFolderName: String
    public let colorPalette: CompetitionColorPalette
    public let adminJudgeIDs: Set<String>
    public let defaultAdminScoringJudgeNames: [String]
    public let blockScopedAdminScoringJudgeNames: [String: [String]]

    public init(
        id: String,
        displayName: String,
        logoAssetName: String,
        heroFallbackAssetName: String,
        driveRootFolderName: String,
        colorPalette: CompetitionColorPalette = .levitate,
        adminJudgeIDs: Set<String>,
        defaultAdminScoringJudgeNames: [String],
        blockScopedAdminScoringJudgeNames: [String: [String]] = [:]
    ) {
        self.id = id
        self.displayName = displayName
        self.logoAssetName = logoAssetName
        self.heroFallbackAssetName = heroFallbackAssetName
        self.driveRootFolderName = driveRootFolderName
        self.colorPalette = colorPalette
        self.adminJudgeIDs = adminJudgeIDs
        self.defaultAdminScoringJudgeNames = defaultAdminScoringJudgeNames
        self.blockScopedAdminScoringJudgeNames = blockScopedAdminScoringJudgeNames
    }

    public func adminScoringJudgeNames(for block: DanceBlock?) -> [String] {
        guard let block else {
            return defaultAdminScoringJudgeNames
        }

        let candidates = [block.id, block.name, block.title].map(\.normalizedKey)
        for candidate in candidates {
            if let names = blockScopedAdminScoringJudgeNames[candidate] {
                return names
            }
        }

        return defaultAdminScoringJudgeNames
    }
}

public extension CompetitionBranding {
    static let levitate = CompetitionBranding(
        id: "levitate",
        displayName: "Levitate",
        logoAssetName: "LevitateLogo",
        heroFallbackAssetName: "LevitateDancerHero",
        driveRootFolderName: "FEEDBACK LEVITATE MX",
        colorPalette: .levitate,
        adminJudgeIDs: ["ati"],
        defaultAdminScoringJudgeNames: ["DANIEL", "ALEX", "VLADIMIR"],
        blockScopedAdminScoringJudgeNames: [
            "4": ["DANIEL", "ANGELA", "YOLI"],
            "BLOQUE 4": ["DANIEL", "ANGELA", "YOLI"],
            "BLOQUE 04": ["DANIEL", "ANGELA", "YOLI"]
        ]
    )

    static let auroraCircuit = CompetitionBranding(
        id: "aurora-circuit",
        displayName: "Aurora Circuit",
        logoAssetName: "AuroraCircuitLogo",
        heroFallbackAssetName: "AuroraCircuitHero",
        driveRootFolderName: "FEEDBACK AURORA CIRCUIT",
        colorPalette: .auroraCircuit,
        adminJudgeIDs: ["director"],
        defaultAdminScoringJudgeNames: ["NOVA", "MARA", "ELI"],
        blockScopedAdminScoringJudgeNames: [
            "FINAL": ["NOVA", "MARA", "SOL"],
            "BLOQUE FINAL": ["NOVA", "MARA", "SOL"],
            "SHOWCASE": ["ELI", "SOL", "RIO"]
        ]
    )

    static let prismaOpen = CompetitionBranding(
        id: "prisma-open",
        displayName: "Prisma Open",
        logoAssetName: "PrismaOpenLogo",
        heroFallbackAssetName: "PrismaOpenHero",
        driveRootFolderName: "FEEDBACK PRISMA OPEN",
        colorPalette: .prismaOpen,
        adminJudgeIDs: ["admin"],
        defaultAdminScoringJudgeNames: ["LUNA", "MAX", "SARA"],
        blockScopedAdminScoringJudgeNames: [
            "PRO": ["LUNA", "MAX", "NOA"],
            "BLOQUE PRO": ["LUNA", "MAX", "NOA"],
            "MASTER": ["SARA", "NOA", "MAX"]
        ]
    )

    static let allBrands = [
        levitate,
        auroraCircuit,
        prismaOpen
    ]

    static func brand(id rawID: String?) -> CompetitionBranding? {
        guard let normalizedID = rawID?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
              !normalizedID.isEmpty else {
            return nil
        }

        return allBrands.first { $0.id == normalizedID }
    }
}
