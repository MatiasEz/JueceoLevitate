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
                            DictamenView(results: store.rankings, onExportPDF: exportPDF)
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
        store.exportPDF()
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
        let preview = Array((blockPending + extraPending).prefix(5))
        return preview.isEmpty ? Array(orderedRoutines.prefix(5)) : preview
    }

    private var completedCount: Int {
        store.rankings.filter { $0.total > 0 }.count
    }

    private var syncPercent: Int {
        store.pendingSyncCount == 0 ? 100 : max(0, 100 - store.pendingSyncCount * 8)
    }

    var body: some View {
        GeometryReader { proxy in
            let isCompactHeight = proxy.size.height < 830
            let pagePadding: CGFloat = isCompactHeight ? 28 : 38
            let contentSpacing: CGFloat = isCompactHeight ? 14 : 22
            let heroHeight: CGFloat = isCompactHeight ? 170 : max(230, min(290, proxy.size.height * 0.32))

            VStack(spacing: 0) {
                VStack(spacing: 0) {
                    topBar
                }
                .padding(.horizontal, pagePadding)
                .padding(.top, isCompactHeight ? 24 : 34)
                .padding(.bottom, isCompactHeight ? 10 : 18)

                VStack(spacing: contentSpacing) {
                    HStack(alignment: .center, spacing: 34) {
                        greeting
                            .frame(width: min(420, proxy.size.width * 0.34), alignment: .leading)

                        Spacer(minLength: 14)

                        DancerHero()
                            .frame(maxWidth: min(610, proxy.size.width * 0.52), maxHeight: .infinity)
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: heroHeight)

                    metrics
                        .frame(maxWidth: .infinity)

                    pendingRoutinesCard(isCompact: isCompactHeight)
                        .frame(maxWidth: .infinity)

                    Spacer(minLength: 12)

                    enterJudgingButton
                }
                .frame(maxWidth: 1180, alignment: .top)
                .frame(maxHeight: .infinity, alignment: .top)
                .padding(.horizontal, pagePadding)
                .padding(.bottom, isCompactHeight ? 24 : 34)
            }
        }
        .background(DashboardBackground())
    }

    private var topBar: some View {
        HStack(spacing: 28) {
            LevitBrand()

            Spacer()

            EventPill()
            SyncPill(status: store.syncStatus, pendingCount: store.pendingSyncCount)

            Button {
                addingJudge = true
            } label: {
                HStack(spacing: 12) {
                    Text(String(store.selectedJudge.prefix(2)))
                        .font(.caption.weight(.bold))
                        .frame(width: 42, height: 42)
                        .background(LevitTheme.softFill, in: Circle())
                    VStack(alignment: .leading, spacing: 2) {
                        Text(store.selectedJudge)
                            .font(.headline.weight(.bold))
                        Text("Juez")
                            .font(.caption)
                            .foregroundStyle(LevitTheme.muted)
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

    private var greeting: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Buenos dias,")
                .font(.title2.weight(.semibold))
                .foregroundStyle(LevitTheme.muted)
            Text(store.selectedJudge)
                .font(.system(size: 58, weight: .black, design: .rounded))
                .foregroundStyle(LevitTheme.pink)
                .lineLimit(1)
                .minimumScaleFactor(0.55)
            Text("Estas lista para calificar.\nQue comience el flow!")
                .font(.title3.weight(.medium))
                .foregroundStyle(LevitTheme.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var metrics: some View {
        HStack(spacing: 18) {
            MetricCard(icon: "calendar.badge.checkmark", value: "\(completedCount)", label: "Calificadas", detail: "\(percentage(completedCount, store.routines.count))% del bloque")
            MetricCard(icon: "clock", value: nextRoutine?.time.isEmpty == false ? nextRoutine!.time : "00:42", label: "Proxima rutina", detail: nextRoutine.map { "#\($0.id) \($0.name)" } ?? "Sin rutina")
            MetricCard(icon: "star", value: averageScore, label: "Promedio actual", detail: "Tu promedio general")
            MetricCard(icon: "checkmark.circle", value: "\(syncPercent)%", label: "Sincronizacion", detail: store.pendingSyncCount == 0 ? "Todo al dia" : "\(store.pendingSyncCount) pendiente")
        }
    }

    private func pendingRoutinesCard(isCompact: Bool) -> some View {
        VStack(alignment: .leading, spacing: isCompact ? 10 : 13) {
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

            VStack(spacing: isCompact ? 4 : 8) {
                ForEach(Array(pendingPreviewRoutines.enumerated()), id: \.element.id) { index, routine in
                    DashboardRoutineRow(
                        routine: routine,
                        position: index + 1,
                        isPrimary: !isCompact && index == 0,
                        isSelected: routine.id == nextRoutine?.id
                    ) {
                        store.selectedRoutineID = routine.id
                        section = .jueceo
                    }
                }
            }
        }
        .padding(isCompact ? 16 : 20)
        .frame(height: isCompact ? 286 : 342, alignment: .top)
        .background(LevitTheme.surface, in: RoundedRectangle(cornerRadius: 24))
        .overlay(RoundedRectangle(cornerRadius: 24).stroke(LevitTheme.cardStroke))
        .shadow(color: .black.opacity(0.05), radius: 22, x: 0, y: 12)
    }

    private var enterJudgingButton: some View {
        Button {
            section = .jueceo
        } label: {
            Label("Entrar al jueceo", systemImage: "play.fill")
                .font(.system(size: 24, weight: .black, design: .rounded))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 22)
                .foregroundStyle(.white)
                .background(LevitTheme.pinkGradient, in: RoundedRectangle(cornerRadius: 22))
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
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "figure.dance")
                .font(.system(size: 30, weight: .bold))
                .foregroundStyle(LevitTheme.pink)
            VStack(alignment: .leading, spacing: 1) {
                Text("LEVITATE")
                    .font(.system(size: 20, weight: .black))
                    .tracking(4)
                Text("JUDGING SYSTEM")
                    .font(.system(size: 8, weight: .bold))
                    .tracking(3)
                    .foregroundStyle(LevitTheme.muted)
            }
        }
        .foregroundStyle(LevitTheme.ink)
    }
}

struct EventPill: View {
    @EnvironmentObject private var store: JudgingStore

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
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(currentTitle)
                        .font(.headline.weight(.bold))
                    Image(systemName: "chevron.down")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(LevitTheme.muted)
                }
                Text("\(store.routines.count) coreografias")
                    .font(.caption)
                    .foregroundStyle(LevitTheme.muted)
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

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)
                .padding(.top, 5)

            VStack(alignment: .leading, spacing: 3) {
                Text(status.title)
                    .font(.headline.weight(.bold))
                    .foregroundStyle(LevitTheme.ink)
                Text(pendingCount > 0 ? "\(pendingCount) cambios pendientes" : "Sincronizado hace 30 seg")
                    .font(.caption)
                    .foregroundStyle(LevitTheme.muted)
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

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.headline.weight(.bold))
                    .foregroundStyle(LevitTheme.pink)
                    .frame(width: 34, height: 34)
                    .background(LevitTheme.palePink, in: Circle())

                Text(value)
                    .font(.title2.weight(.black))
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
        .padding(16)
        .frame(maxWidth: .infinity, minHeight: 116, maxHeight: 116, alignment: .leading)
        .background(LevitTheme.surface, in: RoundedRectangle(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(LevitTheme.cardStroke))
        .shadow(color: .black.opacity(0.045), radius: 18, x: 0, y: 10)
    }
}

private struct DashboardRoutineRow: View {
    let routine: Routine
    let position: Int
    let isPrimary: Bool
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: isPrimary ? 16 : 14) {
                Text("#\(routine.id)")
                    .font(isPrimary ? .title3.monospacedDigit().weight(.black) : .callout.monospacedDigit().weight(.black))
                    .foregroundStyle(isSelected || isPrimary ? LevitTheme.pink : LevitTheme.ink)
                    .frame(width: isPrimary ? 68 : 58, height: isPrimary ? 54 : nil, alignment: .center)
                    .background(isPrimary ? LevitTheme.palePink : Color.clear, in: RoundedRectangle(cornerRadius: 14))

                VStack(alignment: .leading, spacing: isPrimary ? 4 : 2) {
                    Text(routine.name)
                        .font(isPrimary ? .title3.weight(.black) : .callout.weight(.black))
                        .foregroundStyle(LevitTheme.ink)
                        .lineLimit(1)
                    Text(routine.academy)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(LevitTheme.muted)
                        .lineLimit(1)
                }

                Spacer()

                HStack(spacing: 6) {
                    LevitTag(routine.category)
                    LevitTag(routine.genre)
                }
                .frame(maxWidth: 190, alignment: .trailing)

                if isPrimary {
                    Label("Entrar", systemImage: "play.fill")
                        .font(.caption.weight(.black))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .foregroundStyle(.white)
                        .background(LevitTheme.pinkGradient, in: Capsule())
                } else {
                    Image(systemName: isSelected ? "play.fill" : "chevron.right")
                        .font(.caption.weight(.black))
                        .foregroundStyle(isSelected ? LevitTheme.pink : LevitTheme.muted.opacity(0.65))
                        .frame(width: 20)
                }
            }
            .padding(.horizontal, isPrimary ? 14 : 12)
            .padding(.vertical, isPrimary ? 7 : 6)
            .frame(height: isPrimary ? 68 : 36)
            .background(isSelected ? LevitTheme.palePink.opacity(0.82) : LevitTheme.softFill, in: RoundedRectangle(cornerRadius: isPrimary ? 16 : 12))
            .overlay(RoundedRectangle(cornerRadius: isPrimary ? 16 : 12).stroke(isSelected ? LevitTheme.pink.opacity(0.16) : .clear))
        }
        .buttonStyle(.plain)
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
    var body: some View {
        ZStack {
            ForEach(0..<7) { index in
                Capsule()
                    .fill(index.isMultiple(of: 2) ? LevitTheme.pink.opacity(0.09) : LevitTheme.softFill)
                    .frame(width: 250 + CGFloat(index * 25), height: 12)
                    .rotationEffect(.degrees(Double(index) * 16 - 52))
                    .offset(x: CGFloat(index * 6) - 20, y: CGFloat(index * 8) - 22)
                    .blur(radius: 5)
            }

            Image(systemName: "figure.dance")
                .font(.system(size: 128, weight: .thin))
                .foregroundStyle(
                    LinearGradient(colors: [.gray.opacity(0.48), LevitTheme.pink.opacity(0.72)], startPoint: .top, endPoint: .bottom)
                )
                .shadow(color: LevitTheme.pink.opacity(0.18), radius: 34, x: 0, y: 12)
        }
        .accessibilityHidden(true)
    }
}
