import SwiftUI

#if canImport(UIKit)
import UIKit
#endif

enum AppSection: String, CaseIterable, Identifiable {
    case inicio = "Home"
    case admin = "Panel admin"
    case editarCalificaciones = "Editar calificaciones"
    case actividad = "Actividad"
    case favoritos = "Favoritos"
    case bloques = "Rutinas"
    case jueceo = "Jueceo"
    case calificaciones = "Ranking en vivo"
    case dictamen = "Dictamen final"
    case importar = "Importar Excel"

    var id: String { rawValue }

    var symbol: String {
        switch self {
        case .inicio: "house"
        case .admin: "gearshape.fill"
        case .editarCalificaciones: "tablecells.fill"
        case .actividad: "dot.radiowaves.left.and.right"
        case .favoritos: "star.fill"
        case .bloques: "list.bullet"
        case .jueceo: "checklist"
        case .calificaciones: "chart.bar.fill"
        case .dictamen: "trophy.fill"
        case .importar: "square.and.arrow.up"
        }
    }

    var requiresAdmin: Bool {
        switch self {
        case .inicio, .bloques, .jueceo:
            false
        case .admin, .editarCalificaciones, .actividad, .favoritos, .calificaciones, .dictamen, .importar:
            true
        }
    }

    static let adminNavigation: [AppSection] = [
        .inicio,
        .editarCalificaciones,
        .dictamen,
        .favoritos,
        .importar
    ]

    static let judgeNavigation: [AppSection] = [
        .inicio,
        .bloques,
        .jueceo
    ]
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
    @State private var isSavingJudge = false
    @State private var sharing = false

    var body: some View {
        let activeSection = routedSection(for: section)

        ZStack {
            LevitTheme.paper.ignoresSafeArea()

            Group {
                if activeSection == .inicio {
                    DashboardView(
                        section: $section,
                        addingJudge: $addingJudge,
                        onExportPDF: exportPDF
                    )
                } else if activeSection == .jueceo {
                    JudgingView(routines: store.visibleRoutines, addingJudge: $addingJudge) {
                        if store.isAdminEditingAsJudge {
                            store.clearAdminScoringOverride()
                            section = .editarCalificaciones
                        } else {
                            section = store.canAccess(.bloques) ? .bloques : .inicio
                        }
                    } onFinishedBlock: {
                        section = .inicio
                    }
                } else {
                    HStack(spacing: 0) {
                        LevitSidebar(section: $section)
                            .fixedSize(horizontal: true, vertical: false)
                            .layoutPriority(10)

                        switch activeSection {
                        case .inicio:
                            EmptyView()
                        case .admin:
                            AdminView(section: $section, onExportPDF: exportPDF)
                        case .editarCalificaciones:
                            ScoreEditorView(section: $section)
                        case .actividad:
                            JudgeActivityView()
                        case .favoritos:
                            FavoritesView()
                        case .bloques:
                            BlocksView(
                                blocks: store.selectedBlock.map { [$0] } ?? store.blocks,
                                routines: store.visibleRoutines
                            ) { routine in
                                openJudging(for: routine)
                            }
                        case .jueceo:
                            EmptyView()
                        case .calificaciones:
                            ScoresView(results: store.rankings, onExportPDF: exportPDF)
                        case .dictamen:
                            DictamenView(results: store.rankings)
                        case .importar:
                            ExcelImportView()
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                }
            }

            if store.isLoadingBackendData {
                BackendLoadingOverlay(message: store.backendLoadingMessage)
                    .transition(.opacity.combined(with: .scale(scale: 0.98)))
                    .zIndex(10)
            }

            if let notice = store.operationNotice {
                VStack {
                    OperationNoticeBanner(notice: notice) {
                        store.dismissOperationNotice()
                    }
                    .padding(.top, 18)
                    .padding(.horizontal, 24)

                    Spacer()
                }
                .transition(.move(edge: .top).combined(with: .opacity))
                .zIndex(20)
            }
        }
        .animation(.easeInOut(duration: 0.18), value: store.isLoadingBackendData)
        .animation(.spring(response: 0.28, dampingFraction: 0.86), value: store.operationNotice?.id)
        .alert("Nuevo juez", isPresented: $addingJudge) {
            TextField("Nombre", text: $newJudgeName)
            Button("Agregar") {
                let name = newJudgeName
                newJudgeName = ""
                Task { await addJudge(name) }
            }
            .disabled(isSavingJudge)
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
        .onChange(of: store.selectedJudge) { _, _ in
            if !store.canAccess(section) {
                section = .inicio
            } else if shouldRouteAdminToJudgePicker {
                section = .editarCalificaciones
            }
        }
        .onChange(of: store.isAdminEditingAsJudge) { _, _ in
            if shouldRouteAdminToJudgePicker {
                section = .editarCalificaciones
            }
        }
    }

    private func exportPDF() {
        exportPDF(results: nil, title: "Calificaciones y dictamen final")
    }

    private func exportPDF(results: [RoutineResult]?, title: String) {
        store.exportPDF(results: results, title: title)
        sharing = store.lastPDFURL != nil
    }

    @MainActor
    private func addJudge(_ name: String) async {
        isSavingJudge = true
        defer { isSavingJudge = false }

        do {
            if let savedName = try await store.addJudge(name) {
                store.showOperationSuccess("Juez agregado", message: "\(savedName) quedó guardado en el programa actual.")
            }
        } catch {
            store.showOperationFailure("No se pudo agregar juez", message: error.localizedDescription)
        }
    }

    private var shouldRouteAdminToJudgePicker: Bool {
        section == .jueceo && store.isAdmin && !store.isAdminEditingAsJudge
    }

    private func routedSection(for requestedSection: AppSection) -> AppSection {
        if requestedSection == .calificaciones {
            return store.canAccess(.dictamen) ? .dictamen : .inicio
        }
        if requestedSection == .admin {
            return store.canAccess(.editarCalificaciones) ? .editarCalificaciones : .inicio
        }
        let allowedSection = store.canAccess(requestedSection) ? requestedSection : .inicio
        if allowedSection == .jueceo && store.isAdmin && !store.isAdminEditingAsJudge {
            return .editarCalificaciones
        }
        return allowedSection
    }

    private func openJudging(for routine: Routine? = nil) {
        if let routine {
            store.selectedRoutineID = routine.id
        }
        section = store.isAdmin && !store.isAdminEditingAsJudge ? .editarCalificaciones : .jueceo
    }
}

private struct BackendLoadingOverlay: View {
    let message: String

    var body: some View {
        ZStack {
            LevitTheme.paper.opacity(0.82)
                .ignoresSafeArea()

            VStack(spacing: 18) {
                ProgressView()
                    .controlSize(.large)
                    .tint(LevitTheme.pink)

                VStack(spacing: 6) {
                    Text("Cargando datos")
                        .font(.title3.weight(.black))
                        .foregroundStyle(LevitTheme.ink)
                    Text(message)
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(LevitTheme.muted)
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                }
            }
            .padding(.horizontal, 34)
            .padding(.vertical, 28)
            .frame(width: 360)
            .background(LevitTheme.elevatedSurface, in: RoundedRectangle(cornerRadius: 22))
            .overlay(RoundedRectangle(cornerRadius: 22).stroke(LevitTheme.line))
            .shadow(color: .black.opacity(0.10), radius: 28, x: 0, y: 14)
        }
    }
}

struct OperationNoticeBanner: View {
    let notice: OperationNotice
    var isCompact = false
    let onDismiss: () -> Void

    private var color: Color {
        switch notice.kind {
        case .success: .green
        case .failure: .red
        }
    }

    private var symbol: String {
        switch notice.kind {
        case .success: "checkmark.circle.fill"
        case .failure: "exclamationmark.triangle.fill"
        }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: symbol)
                .font(.title3.weight(.bold))
                .foregroundStyle(color)
                .frame(width: 28, height: 28)

            VStack(alignment: .leading, spacing: 4) {
                Text(notice.title)
                    .font((isCompact ? Font.callout : .headline).weight(.black))
                    .foregroundStyle(LevitTheme.ink)
                Text(notice.message)
                    .font((isCompact ? Font.caption : .subheadline).weight(.semibold))
                    .foregroundStyle(LevitTheme.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 8)

            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.caption.weight(.black))
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(.plain)
            .foregroundStyle(LevitTheme.muted)
        }
        .padding(.vertical, isCompact ? 12 : 14)
        .padding(.leading, isCompact ? 14 : 16)
        .padding(.trailing, 10)
        .frame(maxWidth: isCompact ? .infinity : 620)
        .background(LevitTheme.solidSurface, in: RoundedRectangle(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(color.opacity(0.28), lineWidth: 1))
        .shadow(color: .black.opacity(0.18), radius: 24, x: 0, y: 14)
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
        store.visibleRoutines.sorted { lhs, rhs in
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

            ScrollView {
                dashboardStack(
                    pagePadding: pagePadding,
                    topPadding: topPadding,
                    bottomPadding: bottomPadding,
                    contentSpacing: contentSpacing,
                    heroHeight: heroHeight,
                    contentWidth: proxy.size.width,
                    isCompactHeight: isPhoneLandscape ? true : isCompactHeight,
                    isPhoneLandscape: isPhoneLandscape
                )
                .frame(minHeight: proxy.size.height, alignment: .top)
            }
            .scrollIndicators(.hidden)
        }
        .background(DashboardBackground())
        .task {
            await store.reportJudgeAtHome()
        }
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
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: heroHeight)

                    metrics(isCompact: isCompactHeight)
                        .frame(maxWidth: .infinity)
                }
                .frame(maxWidth: 1180, alignment: .top)
                .padding(.horizontal, pagePadding)
                .padding(.bottom, contentSpacing)
            }
            .background(alignment: .trailing) {
                DashboardHeroBackground(widthFraction: 2.0 / 3.0)
            }

            VStack(spacing: contentSpacing) {
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
            BlockPill(isCompact: isCompact)
            SyncPill(status: store.syncStatus, pendingCount: store.pendingSyncCount, isCompact: isCompact)
            JudgePill(addingJudge: $addingJudge, isCompact: isCompact)
        }
    }

    private func greeting(isPhoneLandscape: Bool) -> some View {
        VStack(alignment: .leading, spacing: isPhoneLandscape ? 4 : 8) {
            Text("Buenos días,")
                .font((isPhoneLandscape ? Font.callout : .title2).weight(.semibold))
                .foregroundStyle(LevitTheme.muted)
            Text(store.selectedJudge)
                .font(.system(size: isPhoneLandscape ? 36 : 58, weight: .black, design: .rounded))
                .foregroundStyle(LevitTheme.pink)
                .lineLimit(1)
                .minimumScaleFactor(0.55)
            Text("¡Que comience el flow!")
                .font((isPhoneLandscape ? Font.callout : .title3).weight(.medium))
                .foregroundStyle(LevitTheme.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func metrics(isCompact: Bool) -> some View {
        HStack(spacing: isCompact ? 10 : 18) {
            MetricCard(icon: "calendar.badge.checkmark", value: "\(completedCount)", label: "Calificadas", detail: "\(percentage(completedCount, store.visibleRoutines.count))% del bloque", isCompact: isCompact)
            MetricCard(icon: "checkmark.circle", value: "\(syncPercent)%", label: "Sincronización", detail: store.pendingSyncCount == 0 ? "Todo al día" : "\(store.pendingSyncCount) pendiente", isCompact: isCompact)
        }
    }

    private func pendingRoutinesCard(isCompact: Bool) -> some View {
        VStack(alignment: .leading, spacing: isCompact ? 7 : 9) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Próximas coreografías")
                        .font(.headline.weight(.black))
                        .foregroundStyle(LevitTheme.ink)
                    Text("Pendientes en orden de salida")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(LevitTheme.muted)
                }

                Spacer()

                if !store.isAdmin && store.canAccess(.bloques) {
                    Button {
                        section = .bloques
                    } label: {
                        Label("Ver todas", systemImage: "eye")
                            .font(.callout.weight(.bold))
                            .padding(.horizontal, 16)
                            .padding(.vertical, 11)
                            .foregroundStyle(LevitTheme.ink)
                            .background(LevitTheme.softFill, in: RoundedRectangle(cornerRadius: 13))
                            .contentShape(RoundedRectangle(cornerRadius: 13))
                    }
                    .buttonStyle(.plain)
                }
            }

            VStack(spacing: isCompact ? 6 : 8) {
                ForEach(Array(pendingPreviewRoutines.enumerated()), id: \.element.id) { index, routine in
                    DashboardRoutineCard(
                        routine: routine,
                        position: index + 1,
                        isSelected: routine.id == nextRoutine?.id,
                        isCompact: isCompact
                    ) {
                        openJudging(for: routine)
                    }
                }
            }
        }
    }

    private func enterJudgingButton(isCompact: Bool) -> some View {
        HStack(spacing: isCompact ? 10 : 14) {
            Button {
                if store.isAdmin {
                    section = .editarCalificaciones
                    return
                }
                if let nextRoutine {
                    store.selectedRoutineID = nextRoutine.id
                }
                section = .jueceo
            } label: {
                Label(store.isAdmin ? "Editar calificaciones" : "Entrar al jueceo", systemImage: store.isAdmin ? "tablecells.fill" : "play.fill")
                    .font(.system(size: isCompact ? 18 : 24, weight: .black, design: .rounded))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .frame(maxWidth: .infinity)
                    .frame(minWidth: 0)
                    .padding(.vertical, isCompact ? 16 : 22)
                    .foregroundStyle(.white)
                    .background(LevitTheme.pinkGradient, in: RoundedRectangle(cornerRadius: isCompact ? 18 : 22))
                    .shadow(color: LevitTheme.pink.opacity(0.24), radius: 18, x: 0, y: 10)
                    .contentShape(RoundedRectangle(cornerRadius: isCompact ? 18 : 22))
            }
            .buttonStyle(.plain)
            .disabled(!store.isAdmin && nextRoutine == nil)
            .opacity(!store.isAdmin && nextRoutine == nil ? 0.45 : 1)
        }
    }

    private func openJudging(for routine: Routine) {
        store.selectedRoutineID = routine.id
        section = store.isAdmin && !store.isAdminEditingAsJudge ? .editarCalificaciones : .jueceo
    }

    private func percentage(_ value: Int, _ total: Int) -> Int {
        guard total > 0 else { return 0 }
        return Int((Double(value) / Double(total) * 100).rounded())
    }
}

struct LevitSidebar: View {
    @EnvironmentObject private var store: JudgingStore
    @Binding var section: AppSection

    var body: some View {
        VStack(spacing: 28) {
            Image(systemName: "figure.dance")
                .font(.title2.weight(.bold))
                .foregroundStyle(LevitTheme.pink)
                .frame(width: 42, height: 42)

            VStack(spacing: 18) {
                ForEach(visibleSections) { item in
                    Button {
                        section = item == .jueceo && store.isAdmin && !store.isAdminEditingAsJudge ? .editarCalificaciones : item
                    } label: {
                        SidebarItemIcon(item: item, isSelected: section == item)
                    }
                    .frame(
                        minWidth: 44,
                        idealWidth: 44,
                        maxWidth: 44,
                        minHeight: 44,
                        idealHeight: 44,
                        maxHeight: 44
                    )
                    .fixedSize()
                    .buttonStyle(.plain)
                    .accessibilityLabel(item.rawValue)
                }
            }
            .layoutPriority(1)
            .fixedSize(horizontal: false, vertical: true)

            Spacer()
        }
        .padding(.vertical, 22)
        .frame(minWidth: 74, idealWidth: 74, maxWidth: 74)
        .frame(maxHeight: .infinity, alignment: .top)
        .fixedSize(horizontal: true, vertical: false)
        .background(LevitTheme.sidebarSurface)
        .overlay(alignment: .trailing) {
            Rectangle().fill(LevitTheme.line).frame(width: 1)
        }
    }

    private var visibleSections: [AppSection] {
        let orderedSections = store.isAdmin ? AppSection.adminNavigation : AppSection.judgeNavigation
        return orderedSections.filter { item in
            guard store.canAccess(item) else { return false }
            return item != .jueceo || !store.isAdmin
        }
    }
}

private struct SidebarItemIcon: View {
    let item: AppSection
    let isSelected: Bool

    var body: some View {
        ZStack {
            Image(systemName: item.symbol)
                .font(.system(size: 18, weight: .semibold))
                .frame(width: 24, height: 24)
        }
        .frame(width: 44, height: 44)
        .fixedSize(horizontal: true, vertical: true)
        .foregroundStyle(isSelected ? LevitTheme.pink : LevitTheme.muted)
        .background(isSelected ? LevitTheme.palePink : Color.clear, in: RoundedRectangle(cornerRadius: 14))
        .contentShape(RoundedRectangle(cornerRadius: 14))
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
        Image("LevitateLogo")
            .renderingMode(.template)
            .resizable()
            .scaledToFit()
            .frame(width: isCompact ? 136 : 204, height: isCompact ? 40 : 60, alignment: .leading)
            .foregroundStyle(LevitTheme.ink)
            .accessibilityLabel("Levitate")
    }
}

struct EventPill: View {
    @EnvironmentObject private var store: JudgingStore
    var isCompact = false
    @State private var eventPendingDeletion: EventSummary?
    @State private var isEventDeletionAlertPresented = false
    @State private var isDeletingEvent = false

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

            if !store.availableEvents.isEmpty && store.isAdmin {
                Divider()

                Menu {
                    ForEach(store.availableEvents) { event in
                        Button(role: .destructive) {
                            eventPendingDeletion = event
                            isEventDeletionAlertPresented = true
                        } label: {
                            Label(event.name, systemImage: "trash")
                        }
                    }
                } label: {
                    Label("Borrar programa", systemImage: "trash")
                }
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
                    Text("\(store.routines.count) coreografías")
                        .font(.caption)
                        .foregroundStyle(LevitTheme.muted)
                }
            }
            .foregroundStyle(LevitTheme.ink)
        }
        .alert("Borrar programa", isPresented: $isEventDeletionAlertPresented) {
            Button("Borrar", role: .destructive) {
                guard let event = eventPendingDeletion else { return }
                Task { await deletePendingEvent(event) }
            }
            .disabled(isDeletingEvent)

            Button("Cancelar", role: .cancel) {
                resetPendingDeletion()
            }
        } message: {
            Text("Se va a quitar \(eventPendingDeletion?.name ?? "este programa") de la lista online.")
        }
    }

    private var currentTitle: String {
        store.availableEvents.first { $0.id == store.selectedEventID }?.name
            ?? (store.blocks.first?.name.capitalized ?? "Bloque")
    }

    @MainActor
    private func deletePendingEvent(_ event: EventSummary) async {
        let eventName = event.name
        isDeletingEvent = true
        defer { isDeletingEvent = false }

        do {
            try await store.deleteEvent(event)
            resetPendingDeletion()
            store.showOperationSuccess("Programa borrado", message: "\(eventName) se borró correctamente.")
        } catch {
            resetPendingDeletion()
            store.showOperationFailure("No se pudo borrar programa", message: error.localizedDescription)
        }
    }

    private func resetPendingDeletion() {
        isEventDeletionAlertPresented = false
        eventPendingDeletion = nil
    }
}

struct BlockPill: View {
    @EnvironmentObject private var store: JudgingStore
    var isCompact = false

    var body: some View {
        Menu {
            if store.blocks.isEmpty {
                Text("Sin bloques")
            } else {
                ForEach(store.blocks) { block in
                    Button {
                        store.selectBlock(block)
                    } label: {
                        Label(block.name, systemImage: block.id == store.selectedBlock?.id ? "checkmark.circle.fill" : "circle")
                    }
                }
            }
        } label: {
            VStack(alignment: .leading, spacing: isCompact ? 1 : 4) {
                HStack(spacing: 6) {
                    Text(store.selectedBlock?.name ?? "Bloque")
                        .font((isCompact ? Font.callout : .headline).weight(.bold))
                        .lineLimit(1)
                    Image(systemName: "chevron.down")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(LevitTheme.muted)
                }
                if !isCompact {
                    Text("\(store.visibleRoutines.count) coreografías")
                        .font(.caption)
                        .foregroundStyle(LevitTheme.muted)
                }
            }
            .foregroundStyle(LevitTheme.ink)
        }
    }
}

struct JudgePill: View {
    @EnvironmentObject private var store: JudgingStore
    @Binding var addingJudge: Bool
    var isCompact = false
    @State private var judgePendingDeletion: String?
    @State private var isJudgeDeletionAlertPresented = false
    @State private var isDeletingJudge = false

    var body: some View {
        Menu {
            if store.judges.isEmpty {
                Text("Sin jueces")
            } else {
                ForEach(store.orderedJudges, id: \.self) { judge in
                    Button {
                        store.selectJudge(judge)
                    } label: {
                        Label(judge, systemImage: judge == store.selectedJudge ? "checkmark.circle.fill" : "circle")
                    }
                }
            }

            Divider()

            if !store.deletableJudges.isEmpty {
                Menu {
                    ForEach(store.deletableJudges, id: \.self) { judge in
                        Button(role: .destructive) {
                            judgePendingDeletion = judge
                            isJudgeDeletionAlertPresented = true
                        } label: {
                            Label(judge, systemImage: "trash")
                        }
                    }
                } label: {
                    Label("Borrar juez", systemImage: "trash")
                }

                Divider()
            }

            Button {
                addingJudge = true
            } label: {
                Label("Nuevo juez", systemImage: "person.badge.plus")
            }
        } label: {
            HStack(spacing: isCompact ? 8 : 12) {
                Text(String(store.selectedJudge.prefix(2)))
                    .font(.caption.weight(.bold))
                    .frame(width: isCompact ? 34 : 42, height: isCompact ? 34 : 42)
                    .background(LevitTheme.softFill, in: Circle())

                VStack(alignment: .leading, spacing: 2) {
                    Text(store.selectedJudge)
                        .font((isCompact ? Font.callout : .headline).weight(.bold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.72)
                    if !isCompact {
                        Text(store.roleTitle(for: store.selectedJudge))
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
        .alert("Borrar juez", isPresented: $isJudgeDeletionAlertPresented) {
            Button("Borrar", role: .destructive) {
                guard let judge = judgePendingDeletion else { return }
                Task { await deletePendingJudge(judge) }
            }
            .disabled(isDeletingJudge)

            Button("Cancelar", role: .cancel) {
                resetPendingJudgeDeletion()
            }
        } message: {
            Text(store.hasRemoteConfiguration
                ? "Se va a borrar \(judgePendingDeletion ?? "este juez") del programa actual. También se quitarán sus puntajes, devoluciones, penalizaciones y favoritos."
                : "Se van a borrar sus puntajes, devoluciones, penalizaciones y favoritos locales.")
        }
    }

    @MainActor
    private func deletePendingJudge(_ judge: String) async {
        let judgeName = judge
        isDeletingJudge = true
        defer { isDeletingJudge = false }

        do {
            try await store.deleteJudge(judge)
            resetPendingJudgeDeletion()
            store.showOperationSuccess("Juez borrado", message: "\(judgeName) se borró del programa actual.")
        } catch {
            resetPendingJudgeDeletion()
            store.showOperationFailure("No se pudo borrar juez", message: error.localizedDescription)
        }
    }

    private func resetPendingJudgeDeletion() {
        isJudgeDeletionAlertPresented = false
        judgePendingDeletion = nil
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

struct RefreshDataButton: View {
    let isRefreshing: Bool
    var isCompact = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: isCompact ? 0 : 8) {
                if isRefreshing {
                    ProgressView()
                        .controlSize(.small)
                        .tint(LevitTheme.pink)
                } else {
                    Image(systemName: "arrow.clockwise")
                        .font(.callout.weight(.black))
                }

                if !isCompact {
                    Text(isRefreshing ? "Actualizando" : "Actualizar")
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                }
            }
            .font(.callout.weight(.black))
            .frame(width: isCompact ? 42 : nil, height: isCompact ? 42 : nil)
            .padding(.horizontal, isCompact ? 0 : 14)
            .padding(.vertical, isCompact ? 0 : 10)
            .foregroundStyle(LevitTheme.ink)
            .background(LevitTheme.softFill, in: RoundedRectangle(cornerRadius: isCompact ? 13 : 12))
            .overlay(RoundedRectangle(cornerRadius: isCompact ? 13 : 12).stroke(LevitTheme.line))
            .contentShape(RoundedRectangle(cornerRadius: isCompact ? 13 : 12))
        }
        .buttonStyle(.plain)
        .disabled(isRefreshing)
        .opacity(isRefreshing ? 0.72 : 1)
        .accessibilityLabel(isRefreshing ? "Actualizando datos" : "Actualizar datos")
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
                            Text("Próxima")
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
                            if let level = routine.levelTagText {
                                LevitTag(level)
                            }
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
        .padding(.vertical, isCompact ? 14 : 15)
        .frame(maxWidth: .infinity, minHeight: isCompact ? 70 : 78, maxHeight: isCompact ? 70 : 78, alignment: .leading)
        .background(LevitTheme.surface, in: RoundedRectangle(cornerRadius: 18))
        .overlay {
            RoundedRectangle(cornerRadius: 18)
                .stroke(isSelected ? LevitTheme.pink.opacity(0.24) : LevitTheme.cardStroke, lineWidth: isSelected ? 1.4 : 1)
        }
        .shadow(color: .black.opacity(isSelected ? 0.07 : 0.045), radius: 18, x: 0, y: 10)
        .contentShape(RoundedRectangle(cornerRadius: 18))
        .onTapGesture(perform: action)
    }
}

struct DashboardBackground: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ZStack {
            LevitTheme.paper

            LinearGradient(
                colors: [
                    LevitTheme.dark.opacity(colorScheme == .dark ? 0.98 : 0.22),
                    LevitTheme.dark.opacity(colorScheme == .dark ? 0.90 : 0.08)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
        .ignoresSafeArea()
    }
}

struct DashboardHeroBackground: View {
    @EnvironmentObject private var store: JudgingStore
    @Environment(\.colorScheme) private var colorScheme

    let widthFraction: CGFloat

    private let judgeHeroImages = [
        ("alex", "JudgeHeroAlex"),
        ("angela", "JudgeHeroAngela"),
        ("daniel", "JudgeHeroDaniel"),
        ("vladimir", "JudgeHeroVladimir"),
        ("yoli", "JudgeHeroYoli")
    ]

    private var heroImageName: String {
        let judgeID = store.scoringJudge.stableRemoteID
        let judgeTokens = Set(judgeID.split(separator: "-").map(String.init))
        if let configuredImageName = store.judgeProfiles
            .first(where: { $0.judgeID == judgeID || $0.name.normalizedKey == store.scoringJudge.normalizedKey })?
            .heroImageName?
            .trimmingCharacters(in: .whitespacesAndNewlines),
           !configuredImageName.isEmpty {
            return configuredImageName
        }
        if let exactMatch = judgeHeroImages.first(where: { $0.0 == judgeID }) {
            return exactMatch.1
        }
        if let tokenMatch = judgeHeroImages.first(where: { judgeTokens.contains($0.0) }) {
            return tokenMatch.1
        }
        return "LevitateDancerHero"
    }

    private var showsHeroImage: Bool {
        store.role(for: store.scoringJudge) != .admin
    }

    var body: some View {
        GeometryReader { proxy in
            let imageWidth = max(0, proxy.size.width * widthFraction)

            ZStack(alignment: .trailing) {
                Color.clear

                if showsHeroImage {
                    Image(heroImageName)
                        .resizable()
                        .scaledToFill()
                        .frame(width: imageWidth, height: proxy.size.height, alignment: .trailing)
                        .clipped()
                        .id(heroImageName)

                    LinearGradient(
                        colors: [
                            LevitTheme.paper.opacity(colorScheme == .dark ? 0.98 : 0.88),
                            LevitTheme.paper.opacity(colorScheme == .dark ? 0.72 : 0.50),
                            .clear
                        ],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                    .frame(width: imageWidth, height: proxy.size.height)

                    LinearGradient(
                        colors: [
                            .clear,
                            .clear,
                            LevitTheme.paper.opacity(colorScheme == .dark ? 0.96 : 0.82)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .frame(width: imageWidth, height: proxy.size.height)

                    RadialGradient(
                        colors: [
                            LevitTheme.pink.opacity(colorScheme == .dark ? 0.20 : 0.14),
                            .clear
                        ],
                        center: .trailing,
                        startRadius: 70,
                        endRadius: max(360, imageWidth * 0.70)
                    )
                    .frame(width: imageWidth, height: proxy.size.height)
                }
            }
        }
        .allowsHitTesting(false)
    }
}
