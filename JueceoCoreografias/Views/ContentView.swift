import SwiftUI

#if canImport(UIKit)
import UIKit
#endif

enum AppSection: String, CaseIterable, Identifiable {
    case inicio = "Inicio"
    case bloques = "Coreografias"
    case jueceo = "Jueceo"
    case calificaciones = "Ranking"
    case dictamen = "Dictamen"

    var id: String { rawValue }

    var symbol: String {
        switch self {
        case .inicio: "house"
        case .bloques: "list.bullet"
        case .jueceo: "checklist"
        case .calificaciones: "chart.bar.fill"
        case .dictamen: "trophy.fill"
        }
    }

    var isDark: Bool {
        self == .jueceo || self == .calificaciones
    }
}

enum LevitTheme {
    static let pink = Color(red: 0.93, green: 0.16, blue: 0.45)
    static let hotPink = Color(red: 1.0, green: 0.25, blue: 0.56)
    static let palePink = adaptive(light: (1.0, 0.90, 0.94, 1.0), dark: (0.24, 0.08, 0.15, 1.0))
    static let dark = Color(red: 0.045, green: 0.055, blue: 0.075)
    static let darkPanel = Color(red: 0.085, green: 0.10, blue: 0.13)
    static let darkPanel2 = Color(red: 0.115, green: 0.13, blue: 0.16)
    static let ink = adaptive(light: (0.12, 0.13, 0.17, 1.0), dark: (0.94, 0.95, 0.98, 1.0))
    static let muted = adaptive(light: (0.48, 0.49, 0.56, 1.0), dark: (0.64, 0.66, 0.73, 1.0))
    static let paper = adaptive(light: (0.985, 0.985, 0.99, 1.0), dark: (0.045, 0.055, 0.075, 1.0))
    static let surface = adaptive(light: (1.0, 1.0, 1.0, 0.74), dark: (0.115, 0.13, 0.16, 0.78))
    static let solidSurface = adaptive(light: (1.0, 1.0, 1.0, 1.0), dark: (0.115, 0.13, 0.16, 1.0))
    static let elevatedSurface = adaptive(light: (1.0, 1.0, 1.0, 0.88), dark: (0.14, 0.155, 0.19, 0.92))
    static let sidebarSurface = adaptive(light: (1.0, 1.0, 1.0, 0.76), dark: (1.0, 1.0, 1.0, 0.035))
    static let softFill = adaptive(light: (0.0, 0.0, 0.0, 0.045), dark: (1.0, 1.0, 1.0, 0.075))
    static let cardStroke = adaptive(light: (1.0, 1.0, 1.0, 0.86), dark: (1.0, 1.0, 1.0, 0.08))
    static let line = adaptive(light: (0.0, 0.0, 0.0, 0.07), dark: (1.0, 1.0, 1.0, 0.08))
    static let silverPodium = adaptive(light: (0.93, 0.93, 0.95, 1.0), dark: (0.15, 0.16, 0.19, 1.0))
    static let bronzePodium = adaptive(light: (0.98, 0.90, 0.84, 1.0), dark: (0.20, 0.15, 0.12, 1.0))

    static var pinkGradient: LinearGradient {
        LinearGradient(colors: [hotPink, pink], startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    private static func adaptive(
        light: (Double, Double, Double, Double),
        dark: (Double, Double, Double, Double)
    ) -> Color {
        #if canImport(UIKit)
        Color(UIColor { traits in
            let value = traits.userInterfaceStyle == .dark ? dark : light
            return UIColor(
                red: CGFloat(value.0),
                green: CGFloat(value.1),
                blue: CGFloat(value.2),
                alpha: CGFloat(value.3)
            )
        })
        #else
        Color(red: light.0, green: light.1, blue: light.2, opacity: light.3)
        #endif
    }
}

struct ContentView: View {
    @EnvironmentObject private var store: JudgingStore
    @State private var section: AppSection = .inicio
    @State private var addingJudge = false
    @State private var newJudgeName = ""
    @State private var sharing = false

    var body: some View {
        ZStack {
            section.isDark ? LevitTheme.dark.ignoresSafeArea() : LevitTheme.paper.ignoresSafeArea()

            Group {
                if section == .inicio {
                    DashboardView(
                        section: $section,
                        addingJudge: $addingJudge,
                        onExportPDF: exportPDF
                    )
                } else if section == .jueceo {
                    JudgingView(routines: store.routines, addingJudge: $addingJudge) {
                        section = .bloques
                    }
                } else {
                    HStack(spacing: 0) {
                        LevitSidebar(section: $section)

                        switch section {
                        case .inicio:
                            EmptyView()
                        case .bloques:
                            BlocksView(blocks: store.blocks, routines: store.routines) { routine in
                                store.selectedRoutineID = routine.id
                                section = .jueceo
                            }
                        case .jueceo:
                            EmptyView()
                        case .calificaciones:
                            ScoresView(results: store.rankings, onExportPDF: exportPDF)
                        case .dictamen:
                            DictamenView(results: store.rankings) { results, title in
                                exportPDF(results: results, title: title)
                            }
                        }
                    }
                }
            }
        }
        .alert("Nuevo juez", isPresented: $addingJudge) {
            TextField("Nombre", text: $newJudgeName)
            Button("Agregar") {
                store.addJudge(newJudgeName)
                newJudgeName = ""
            }
            Button("Cancelar", role: .cancel) {
                newJudgeName = ""
            }
        }
        .sheet(isPresented: $sharing) {
            if let url = store.lastPDFURL {
                ShareSheet(items: [url])
            }
        }
        .task {
            await store.startRemoteSyncIfAvailable()
        }
    }

    private func exportPDF() {
        exportPDF(results: nil, title: "Calificaciones y Dictamen Final")
    }

    private func exportPDF(results: [RoutineResult]?, title: String) {
        store.exportPDF(results: results, title: title)
        sharing = store.lastPDFURL != nil
    }
}

private struct DashboardView: View {
    @EnvironmentObject private var store: JudgingStore
    @Binding var section: AppSection
    @Binding var addingJudge: Bool
    let onExportPDF: () -> Void

    private var nextRoutine: Routine? {
        pendingPreviewRoutines.first ?? store.selectedRoutine ?? orderedRoutines.first
    }

    private var orderedRoutines: [Routine] {
        store.routines.sorted { lhs, rhs in
            let lhsNumber = Int(lhs.id) ?? Int.max
            let rhsNumber = Int(rhs.id) ?? Int.max
            if lhsNumber == rhsNumber {
                return lhs.id.localizedStandardCompare(rhs.id) == .orderedAscending
            }
            return lhsNumber < rhsNumber
        }
    }

    private var pendingPreviewRoutines: [Routine] {
        let blockName = store.selectedRoutine?.block ?? store.blocks.first?.name ?? ""
        let pending = orderedRoutines.filter { store.result(for: $0).total == 0 }
        let blockPending = pending.filter { $0.block == blockName }
        let extraPending = pending.filter { $0.block != blockName && !blockPending.contains($0) }
        let preview = Array((blockPending + extraPending).prefix(3))
        return preview.isEmpty ? Array(orderedRoutines.prefix(3)) : preview
    }

    private var completedCount: Int {
        store.rankings.filter { $0.total > 0 }.count
    }

    private var syncPercent: Int {
        store.pendingSyncCount == 0 ? 100 : max(0, 100 - store.pendingSyncCount * 8)
    }

    var body: some View {
        GeometryReader { proxy in
            let isPhoneLandscape = proxy.size.height < 560
            let isCompactHeight = proxy.size.height < 830
            let pagePadding: CGFloat = isPhoneLandscape ? 18 : (isCompactHeight ? 26 : 38)
            let contentSpacing: CGFloat = isPhoneLandscape ? 10 : (isCompactHeight ? 12 : 22)
            let heroHeight: CGFloat = isPhoneLandscape ? 96 : (isCompactHeight ? 118 : max(230, min(290, proxy.size.height * 0.32)))
            let topPadding: CGFloat = isPhoneLandscape ? 14 : (isCompactHeight ? 20 : 34)
            let bottomPadding: CGFloat = isPhoneLandscape ? 18 : (isCompactHeight ? 20 : 34)

            Group {
                if isPhoneLandscape {
                    ScrollView {
                        dashboardStack(
                            pagePadding: pagePadding,
                            topPadding: topPadding,
                            bottomPadding: bottomPadding,
                            contentSpacing: contentSpacing,
                            heroHeight: heroHeight,
                            contentWidth: proxy.size.width,
                            isCompactHeight: true,
                            isPhoneLandscape: true
                        )
                        .frame(minHeight: proxy.size.height, alignment: .top)
                    }
                    .scrollIndicators(.hidden)
                } else {
                    dashboardStack(
                        pagePadding: pagePadding,
                        topPadding: topPadding,
                        bottomPadding: bottomPadding,
                        contentSpacing: contentSpacing,
                        heroHeight: heroHeight,
                        contentWidth: proxy.size.width,
                        isCompactHeight: isCompactHeight,
                        isPhoneLandscape: false
                    )
                }
            }
        }
        .background(DashboardBackground())
    }

    private func dashboardStack(
        pagePadding: CGFloat,
        topPadding: CGFloat,
        bottomPadding: CGFloat,
        contentSpacing: CGFloat,
        heroHeight: CGFloat,
        contentWidth: CGFloat,
        isCompactHeight: Bool,
        isPhoneLandscape: Bool
    ) -> some View {
        VStack(spacing: 0) {
            topBar(isCompact: isPhoneLandscape)
                .padding(.horizontal, pagePadding)
                .padding(.top, topPadding)
                .padding(.bottom, isPhoneLandscape ? 8 : (isCompactHeight ? 8 : 18))

            VStack(spacing: contentSpacing) {
                HStack(alignment: .center, spacing: isPhoneLandscape ? 18 : 34) {
                    greeting(isPhoneLandscape: isPhoneLandscape)
                        .frame(width: isPhoneLandscape ? min(260, contentWidth * 0.36) : min(420, contentWidth * 0.34), alignment: .leading)

                    Spacer(minLength: isPhoneLandscape ? 8 : 14)

                    DancerHero(isCompact: isCompactHeight)
                        .frame(maxWidth: isPhoneLandscape ? min(300, contentWidth * 0.42) : min(610, contentWidth * 0.52), maxHeight: .infinity)
                }
                .frame(maxWidth: .infinity)
                .frame(height: heroHeight)

                metrics(isCompact: isCompactHeight)
                    .frame(maxWidth: .infinity)

                pendingRoutinesCard(isCompact: isCompactHeight)
                    .frame(maxWidth: .infinity)

                if !isPhoneLandscape {
                    Spacer(minLength: 6)
                }

                enterJudgingButton(isCompact: isCompactHeight)
            }
            .frame(maxWidth: 1180, alignment: .top)
            .frame(maxHeight: isPhoneLandscape ? nil : .infinity, alignment: .top)
            .padding(.horizontal, pagePadding)
            .padding(.bottom, bottomPadding)
        }
    }

    private func topBar(isCompact: Bool) -> some View {
        HStack(spacing: isCompact ? 12 : 28) {
            LevitBrand(isCompact: isCompact)

            Spacer()

            EventPill(isCompact: isCompact)
            SyncPill(status: store.syncStatus, pendingCount: store.pendingSyncCount, isCompact: isCompact)

            Button {
                addingJudge = true
            } label: {
                HStack(spacing: isCompact ? 8 : 12) {
                    Text(String(store.selectedJudge.prefix(2)))
                        .font(.caption.weight(.bold))
                        .frame(width: isCompact ? 34 : 42, height: isCompact ? 34 : 42)
                        .background(LevitTheme.softFill, in: Circle())
                    VStack(alignment: .leading, spacing: 2) {
                        Text(store.selectedJudge)
                            .font((isCompact ? Font.callout : .headline).weight(.bold))
                        if !isCompact {
                            Text("Juez")
                                .font(.caption)
                                .foregroundStyle(LevitTheme.muted)
                        }
                    }
                    Image(systemName: "chevron.down")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(LevitTheme.muted)
                }
                .foregroundStyle(LevitTheme.ink)
            }
            .buttonStyle(.plain)
        }
    }

    private func greeting(isPhoneLandscape: Bool) -> some View {
        VStack(alignment: .leading, spacing: isPhoneLandscape ? 4 : 8) {
            Text("Buenos dias,")
                .font((isPhoneLandscape ? Font.callout : .title2).weight(.semibold))
                .foregroundStyle(LevitTheme.muted)
            Text(store.selectedJudge)
                .font(.system(size: isPhoneLandscape ? 36 : 58, weight: .black, design: .rounded))
                .foregroundStyle(LevitTheme.pink)
                .lineLimit(1)
                .minimumScaleFactor(0.55)
            Text("Estas lista para calificar.\nQue comience el flow!")
                .font((isPhoneLandscape ? Font.callout : .title3).weight(.medium))
                .foregroundStyle(LevitTheme.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func metrics(isCompact: Bool) -> some View {
        HStack(spacing: isCompact ? 10 : 18) {
            MetricCard(icon: "calendar.badge.checkmark", value: "\(completedCount)", label: "Calificadas", detail: "\(percentage(completedCount, store.routines.count))% del bloque", isCompact: isCompact)
            MetricCard(icon: "clock", value: nextRoutine?.time.isEmpty == false ? nextRoutine!.time : "00:42", label: "Proxima rutina", detail: nextRoutine.map { "#\($0.id) \($0.name)" } ?? "Sin rutina", isCompact: isCompact)
            MetricCard(icon: "star", value: averageScore, label: "Promedio actual", detail: "Tu promedio general", isCompact: isCompact)
            MetricCard(icon: "checkmark.circle", value: "\(syncPercent)%", label: "Sincronizacion", detail: store.pendingSyncCount == 0 ? "Todo al dia" : "\(store.pendingSyncCount) pendiente", isCompact: isCompact)
        }
    }

    private func pendingRoutinesCard(isCompact: Bool) -> some View {
        VStack(alignment: .leading, spacing: isCompact ? 7 : 9) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Proximas coreografias")
                        .font(.headline.weight(.black))
                        .foregroundStyle(LevitTheme.ink)
                    Text("Pendientes en orden de salida")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(LevitTheme.muted)
                }

                Spacer()

                Button {
                    section = .bloques
                } label: {
                    Label("Ver todas", systemImage: "eye")
                        .font(.callout.weight(.bold))
                        .padding(.horizontal, 16)
                        .padding(.vertical, 11)
                        .foregroundStyle(LevitTheme.ink)
                        .background(LevitTheme.softFill, in: RoundedRectangle(cornerRadius: 13))
                }
                .buttonStyle(.plain)
            }

            VStack(spacing: isCompact ? 6 : 8) {
                ForEach(Array(pendingPreviewRoutines.enumerated()), id: \.element.id) { index, routine in
                    DashboardRoutineCard(
                        routine: routine,
                        position: index + 1,
                        isSelected: routine.id == nextRoutine?.id,
                        isCompact: isCompact
                    ) {
                        store.selectedRoutineID = routine.id
                    }
                }
            }
        }
    }

    private func enterJudgingButton(isCompact: Bool) -> some View {
        Button {
            section = .jueceo
        } label: {
            Label("Entrar al jueceo", systemImage: "play.fill")
                .font(.system(size: isCompact ? 18 : 24, weight: .black, design: .rounded))
                .frame(maxWidth: .infinity)
                .padding(.vertical, isCompact ? 16 : 22)
                .foregroundStyle(.white)
                .background(LevitTheme.pinkGradient, in: RoundedRectangle(cornerRadius: isCompact ? 18 : 22))
                .shadow(color: LevitTheme.pink.opacity(0.24), radius: 18, x: 0, y: 10)
        }
        .buttonStyle(.plain)
        .disabled(nextRoutine == nil)
        .opacity(nextRoutine == nil ? 0.45 : 1)
    }

    private var averageScore: String {
        let scored = store.rankings.filter { $0.total > 0 }
        guard !scored.isEmpty else { return "0.00" }
        let average = scored.reduce(0) { $0 + $1.total } / Double(scored.count)
        return average.formatted(.number.precision(.fractionLength(2)))
    }

    private func percentage(_ value: Int, _ total: Int) -> Int {
        guard total > 0 else { return 0 }
        return Int((Double(value) / Double(total) * 100).rounded())
    }
}

struct LevitSidebar: View {
    @Binding var section: AppSection

    var body: some View {
        VStack(spacing: 28) {
            Image(systemName: "figure.dance")
                .font(.title2.weight(.bold))
                .foregroundStyle(LevitTheme.pink)
                .frame(width: 42, height: 42)

            VStack(spacing: 18) {
                ForEach(AppSection.allCases) { item in
                    Button {
                        section = item
                    } label: {
                        Image(systemName: item.symbol)
                            .font(.system(size: 17, weight: .semibold))
                            .frame(width: 44, height: 44)
                            .foregroundStyle(section == item ? LevitTheme.pink : LevitTheme.muted)
                            .background(section == item ? LevitTheme.palePink : Color.clear, in: RoundedRectangle(cornerRadius: 14))
                    }
                    .buttonStyle(.plain)
                }
            }

            Spacer()
        }
        .padding(.vertical, 22)
        .frame(width: 74)
        .background(LevitTheme.sidebarSurface)
        .overlay(alignment: .trailing) {
            Rectangle().fill(LevitTheme.line).frame(width: 1)
        }
    }
}

struct LevitTag: View {
    let text: String
    let dark: Bool

    init(_ text: String, dark: Bool = false) {
        self.text = text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "SIN DATO" : text
        self.dark = dark
    }

    var body: some View {
        Text(text.uppercased())
            .font(.system(size: 11, weight: .black, design: .rounded))
            .lineLimit(1)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .foregroundStyle(dark ? .white.opacity(0.82) : LevitTheme.muted)
            .background(dark ? .white.opacity(0.12) : LevitTheme.softFill, in: Capsule())
    }
}

struct LevitBrand: View {
    var isCompact = false

    var body: some View {
        HStack(spacing: isCompact ? 8 : 12) {
            Image(systemName: "figure.dance")
                .font(.system(size: isCompact ? 22 : 30, weight: .bold))
                .foregroundStyle(LevitTheme.pink)
            VStack(alignment: .leading, spacing: 1) {
                Text("LEVITATE")
                    .font(.system(size: isCompact ? 15 : 20, weight: .black))
                    .tracking(isCompact ? 2.5 : 4)
                if !isCompact {
                    Text("JUDGING SYSTEM")
                        .font(.system(size: 8, weight: .bold))
                        .tracking(3)
                        .foregroundStyle(LevitTheme.muted)
                }
            }
        }
        .foregroundStyle(LevitTheme.ink)
    }
}

struct EventPill: View {
    @EnvironmentObject private var store: JudgingStore
    var isCompact = false

    var body: some View {
        Menu {
            if store.availableEvents.isEmpty {
                Text("Sin eventos online")
            } else {
                ForEach(store.availableEvents) { event in
                    Button {
                        Task { await store.selectEvent(event) }
                    } label: {
                        Label(event.name, systemImage: event.id == store.selectedEventID ? "checkmark.circle.fill" : "circle")
                    }
                }
            }

            Divider()

            Button {
                Task { await store.refreshEvents() }
            } label: {
                Label("Actualizar eventos", systemImage: "arrow.clockwise")
            }
        } label: {
            VStack(alignment: .leading, spacing: isCompact ? 1 : 4) {
                HStack(spacing: 6) {
                    Text(currentTitle)
                        .font((isCompact ? Font.callout : .headline).weight(.bold))
                        .lineLimit(1)
                    Image(systemName: "chevron.down")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(LevitTheme.muted)
                }
                if !isCompact {
                    Text("\(store.routines.count) coreografias")
                        .font(.caption)
                        .foregroundStyle(LevitTheme.muted)
                }
            }
            .foregroundStyle(LevitTheme.ink)
        }
    }

    private var currentTitle: String {
        store.availableEvents.first { $0.id == store.selectedEventID }?.name
            ?? (store.blocks.first?.name.capitalized ?? "Bloque")
    }
}

struct SyncPill: View {
    let status: SyncStatus
    let pendingCount: Int
    var isCompact = false

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)
                .padding(.top, 5)

            VStack(alignment: .leading, spacing: 3) {
                Text(status.title)
                    .font((isCompact ? Font.callout : .headline).weight(.bold))
                    .foregroundStyle(LevitTheme.ink)
                if !isCompact {
                    Text(pendingCount > 0 ? "\(pendingCount) cambios pendientes" : "Sincronizado hace 30 seg")
                        .font(.caption)
                        .foregroundStyle(LevitTheme.muted)
                }
            }
        }
    }

    private var color: Color {
        switch status {
        case .online, .localOnly: .green
        case .connecting, .syncing: .blue
        case .pending: .orange
        case .offline: .red
        }
    }
}

struct MetricCard: View {
    let icon: String
    let value: String
    let label: String
    let detail: String
    var isCompact = false

    var body: some View {
        VStack(alignment: .leading, spacing: isCompact ? 7 : 10) {
            HStack(spacing: isCompact ? 8 : 12) {
                Image(systemName: icon)
                    .font((isCompact ? Font.callout : .headline).weight(.bold))
                    .foregroundStyle(LevitTheme.pink)
                    .frame(width: isCompact ? 28 : 34, height: isCompact ? 28 : 34)
                    .background(LevitTheme.palePink, in: Circle())

                Text(value)
                    .font((isCompact ? Font.title3 : .title2).weight(.black))
                    .foregroundStyle(LevitTheme.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.65)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(label)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(LevitTheme.muted)
                Text(detail)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(LevitTheme.muted.opacity(0.82))
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
            }
        }
        .padding(isCompact ? 12 : 16)
        .frame(maxWidth: .infinity, minHeight: isCompact ? 92 : 116, maxHeight: isCompact ? 92 : 116, alignment: .leading)
        .background(LevitTheme.surface, in: RoundedRectangle(cornerRadius: isCompact ? 16 : 18))
        .overlay(RoundedRectangle(cornerRadius: isCompact ? 16 : 18).stroke(LevitTheme.cardStroke))
        .shadow(color: .black.opacity(0.045), radius: 18, x: 0, y: 10)
    }
}

private struct DashboardRoutineCard: View {
    let routine: Routine
    let position: Int
    let isSelected: Bool
    let isCompact: Bool
    let action: () -> Void

    var body: some View {
        HStack(spacing: isCompact ? 10 : 16) {
            Button(action: action) {
                Text("#\(routine.id)")
                    .font((isCompact ? Font.callout : .headline).monospacedDigit().weight(.black))
                    .foregroundStyle(LevitTheme.pink)
                    .frame(width: isCompact ? 48 : 58, height: isCompact ? 42 : 48)
                    .background(LevitTheme.palePink, in: RoundedRectangle(cornerRadius: 13))
            }
            .buttonStyle(.plain)

            Button(action: action) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(routine.name)
                            .font(.callout.weight(.black))
                            .foregroundStyle(LevitTheme.ink)
                            .lineLimit(1)
                            .minimumScaleFactor(0.78)
                        if isSelected {
                            Text("Proxima")
                                .font(.system(size: 10, weight: .black, design: .rounded))
                                .padding(.horizontal, 7)
                                .padding(.vertical, 4)
                                .foregroundStyle(LevitTheme.pink)
                                .background(LevitTheme.palePink, in: Capsule())
                        }
                    }

                    HStack(spacing: 7) {
                        Text(routine.academy)
                            .font(.caption.weight(.bold))
                            .foregroundStyle(LevitTheme.muted)
                            .lineLimit(1)
                            .minimumScaleFactor(0.75)

                        HStack(spacing: 5) {
                            LevitTag(routine.division)
                            LevitTag(routine.category)
                        }
                    }
                }
            }
            .buttonStyle(.plain)

            Spacer(minLength: isCompact ? 8 : 16)

            Button(action: action) {
                Label("Ver detalles", systemImage: "eye")
                    .font(.caption.weight(.black))
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 9)
                    .foregroundStyle(LevitTheme.ink)
                    .background(LevitTheme.softFill, in: RoundedRectangle(cornerRadius: 12))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, isCompact ? 12 : 14)
        .padding(.vertical, isCompact ? 6 : 7)
        .frame(maxWidth: .infinity, minHeight: isCompact ? 54 : 62, maxHeight: isCompact ? 54 : 62, alignment: .leading)
        .background(LevitTheme.surface, in: RoundedRectangle(cornerRadius: 18))
        .overlay {
            RoundedRectangle(cornerRadius: 18)
                .stroke(isSelected ? LevitTheme.pink.opacity(0.24) : LevitTheme.cardStroke, lineWidth: isSelected ? 1.4 : 1)
        }
        .shadow(color: .black.opacity(isSelected ? 0.07 : 0.045), radius: 18, x: 0, y: 10)
    }
}

private struct DashboardBackground: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ZStack {
            LinearGradient(
                colors: colorScheme == .dark ? darkColors : lightColors,
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            RadialGradient(
                colors: [LevitTheme.pink.opacity(colorScheme == .dark ? 0.18 : 0.16), .clear],
                center: .trailing,
                startRadius: 80,
                endRadius: 560
            )
        }
        .ignoresSafeArea()
    }

    private var lightColors: [Color] {
        [
            Color(red: 0.99, green: 0.99, blue: 1.0),
            Color(red: 0.98, green: 0.95, blue: 0.96),
            Color(red: 1.0, green: 0.98, blue: 0.95)
        ]
    }

    private var darkColors: [Color] {
        [
            LevitTheme.dark,
            Color(red: 0.065, green: 0.075, blue: 0.095),
            Color(red: 0.035, green: 0.043, blue: 0.060)
        ]
    }
}

private struct DancerHero: View {
    var isCompact = false

    var body: some View {
        ZStack {
            ForEach(0..<7) { index in
                Capsule()
                    .fill(index.isMultiple(of: 2) ? LevitTheme.pink.opacity(0.09) : LevitTheme.softFill)
                    .frame(width: (isCompact ? 155 : 250) + CGFloat(index * (isCompact ? 16 : 25)), height: isCompact ? 8 : 12)
                    .rotationEffect(.degrees(Double(index) * 16 - 52))
                    .offset(x: CGFloat(index * 6) - 20, y: CGFloat(index * 8) - 22)
                    .blur(radius: 5)
            }

            Image(systemName: "figure.dance")
                .font(.system(size: isCompact ? 82 : 128, weight: .thin))
                .foregroundStyle(
                    LinearGradient(colors: [.gray.opacity(0.48), LevitTheme.pink.opacity(0.72)], startPoint: .top, endPoint: .bottom)
                )
                .shadow(color: LevitTheme.pink.opacity(0.18), radius: 34, x: 0, y: 12)
        }
        .accessibilityHidden(true)
    }
}
