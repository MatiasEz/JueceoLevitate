import SwiftUI

struct AdminView: View {
    @EnvironmentObject private var store: JudgingStore
    @Binding var section: AppSection
    let onExportPDF: ([RoutineResult]?, String) -> Void

    @State private var selectedJudgeForEdit = ""
    @State private var selectedRoutineIDForEdit = ""
    @State private var searchText = ""

    private var currentEventTitle: String {
        store.availableEvents.first { $0.id == store.selectedEventID }?.name
            ?? store.appData.sourceName
    }

    private var sortedRoutines: [Routine] {
        store.visibleRoutines.sorted { lhs, rhs in
            let lhsNumber = Int(lhs.id) ?? Int.max
            let rhsNumber = Int(rhs.id) ?? Int.max
            if lhsNumber == rhsNumber {
                return lhs.id.localizedStandardCompare(rhs.id) == .orderedAscending
            }
            return lhsNumber < rhsNumber
        }
    }

    private var filteredRoutines: [Routine] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return sortedRoutines }
        return sortedRoutines.filter { routine in
            routine.id.localizedCaseInsensitiveContains(query)
                || routine.name.localizedCaseInsensitiveContains(query)
                || routine.academy.localizedCaseInsensitiveContains(query)
                || routine.genre.localizedCaseInsensitiveContains(query)
                || routine.division.localizedCaseInsensitiveContains(query)
                || routine.category.localizedCaseInsensitiveContains(query)
        }
    }

    private var selectedRoutineForEdit: Routine? {
        sortedRoutines.first { $0.id == selectedRoutineIDForEdit } ?? sortedRoutines.first
    }

    private var completedRoutines: Int {
        store.rankings.filter { $0.total > 0 }.count
    }

    private var completionPercent: Int {
        guard !store.visibleRoutines.isEmpty else { return 0 }
        return Int((Double(completedRoutines) / Double(store.visibleRoutines.count) * 100).rounded())
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                driveExportPanel
                editAsJudgePanel
            }
            .padding(.horizontal, 34)
            .padding(.vertical, 28)
            .frame(maxWidth: 1240, alignment: .leading)
        }
        .background(LevitTheme.paper.ignoresSafeArea())
        .foregroundStyle(LevitTheme.ink)
        .onAppear(perform: normalizeSelection)
        .onChange(of: store.selectedBlock?.id ?? "") { _, _ in normalizeSelection() }
        .onChange(of: store.judges) { _, _ in normalizeSelection() }
        .onChange(of: store.visibleRoutines) { _, _ in normalizeSelection() }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 22) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Panel admin")
                    .font(.system(size: 38, weight: .black, design: .rounded))
                    .foregroundStyle(LevitTheme.ink)
                Text("\(currentEventTitle) - \(store.selectedBlock?.name ?? "Bloque")")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(LevitTheme.muted)
                    .lineLimit(1)
            }

            Spacer()

            HStack(spacing: 18) {
                EventPill()
                BlockPill()
                SyncPill(status: store.syncStatus, pendingCount: store.pendingSyncCount)
            }
        }
    }

    private var metrics: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 210), spacing: 14)], spacing: 14) {
            AdminMetricCard(icon: "square.stack.3d.up.fill", value: "\(store.blocks.count)", label: "Bloques", detail: "\(store.visibleRoutines.count) en vista")
            AdminMetricCard(icon: "figure.dance", value: "\(store.routines.count)", label: "Coreografías", detail: "\(completedRoutines) calificadas")
            AdminMetricCard(icon: "person.3.fill", value: "\(store.editableJudges.count)", label: "Jueces", detail: "ATI administra")
            AdminMetricCard(icon: "checkmark.circle.fill", value: "\(completionPercent)%", label: "Avance", detail: store.pendingSyncCount == 0 ? "Sin pendientes" : "\(store.pendingSyncCount) por subir")
        }
    }

    private var adminActions: some View {
        HStack(spacing: 12) {
            AdminActionButton(title: "Exportar PDF", icon: "doc.richtext") {
                onExportPDF(store.rankings, "Calificaciones y dictamen final")
            }
            AdminActionButton(title: "Actualizar datos", icon: "arrow.clockwise") {
                Task { await store.refreshEvents() }
            }
        }
    }

    private var driveExportPanel: some View {
        HStack(alignment: .top, spacing: 14) {
            ZStack {
                Circle()
                    .fill(driveStatusColor.opacity(0.14))
                    .frame(width: 42, height: 42)
                if store.driveExportStatus.isExporting {
                    ProgressView()
                        .tint(LevitTheme.pink)
                } else {
                    Image(systemName: store.driveExportStatus.systemImage)
                        .font(.headline.weight(.bold))
                        .foregroundStyle(driveStatusColor)
                }
            }

            VStack(alignment: .leading, spacing: 5) {
                Text(store.driveExportStatus.title)
                    .font(.headline.weight(.black))
                    .foregroundStyle(LevitTheme.ink)
                Text(driveStatusMessage)
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(LevitTheme.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer()

            Button {
                guard !store.driveExportStatus.isExporting else { return }
                Task { await store.exportSelectedBlockToDrive() }
            } label: {
                Label("Exportar a Drive", systemImage: "icloud.and.arrow.up")
                    .font(.callout.weight(.black))
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .foregroundStyle(.white)
                    .background(LevitTheme.pinkGradient, in: RoundedRectangle(cornerRadius: 14))
            }
            .buttonStyle(.plain)
            .disabled(store.driveExportStatus.isExporting)
            .opacity(store.driveExportStatus.isExporting ? 0.58 : 1)
        }
        .padding(18)
        .background(LevitTheme.elevatedSurface, in: RoundedRectangle(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(LevitTheme.line))
    }

    private var editAsJudgePanel: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top, spacing: 18) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Editar como juez")
                        .font(.title2.weight(.black))
                }

                Spacer()

                if store.isAdminEditingAsJudge {
                    Button {
                        store.clearAdminScoringOverride()
                    } label: {
                        Label("Salir de edición", systemImage: "xmark.circle")
                            .font(.callout.weight(.black))
                            .padding(.horizontal, 14)
                            .padding(.vertical, 11)
                            .foregroundStyle(LevitTheme.ink)
                            .background(LevitTheme.softFill, in: RoundedRectangle(cornerRadius: 13))
                    }
                    .buttonStyle(.plain)
                }
            }

            HStack(alignment: .top, spacing: 16) {
                VStack(alignment: .leading, spacing: 14) {
                    AdminMenuField(title: "Juez", value: selectedJudgeForEdit.isEmpty ? "Sin jueces" : selectedJudgeForEdit, icon: "person.fill") {
                        ForEach(store.orderedEditableJudges, id: \.self) { judge in
                            Button {
                                selectedJudgeForEdit = judge
                            } label: {
                                Label(judge, systemImage: judge == selectedJudgeForEdit ? "checkmark.circle.fill" : "circle")
                            }
                        }
                    }

                    if let routine = selectedRoutineForEdit {
                        AdminSelectedRoutineCard(
                            routine: routine,
                            judge: selectedJudgeForEdit,
                            total: judgeTotal(for: routine, judge: selectedJudgeForEdit),
                            maxScore: store.template(for: routine).maxScore
                        )

                        Button {
                            store.beginAdminScoring(judge: selectedJudgeForEdit, routine: routine)
                            section = .jueceo
                        } label: {
                            Label("Abrir hoja de jueceo", systemImage: "pencil.and.list.clipboard")
                                .font(.headline.weight(.black))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 17)
                                .foregroundStyle(.white)
                                .background(LevitTheme.pinkGradient, in: RoundedRectangle(cornerRadius: 16))
                        }
                        .buttonStyle(.plain)
                        .disabled(selectedJudgeForEdit.isEmpty)
                        .opacity(selectedJudgeForEdit.isEmpty ? 0.45 : 1)
                    }
                }
                .frame(width: 340)

                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 12) {
                        Label("Coreografías del bloque", systemImage: "list.bullet.rectangle")
                            .font(.headline.weight(.black))
                        Spacer()
                        HStack(spacing: 8) {
                            Image(systemName: "magnifyingglass")
                                .foregroundStyle(LevitTheme.muted)
                            TextField("Buscar", text: $searchText)
                                .textInputAutocapitalization(.never)
                        }
                        .font(.callout.weight(.semibold))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                        .frame(width: 260)
                        .background(LevitTheme.softFill, in: RoundedRectangle(cornerRadius: 13))
                    }

                    VStack(spacing: 8) {
                        ForEach(filteredRoutines) { routine in
                            AdminRoutineEditRow(
                                routine: routine,
                                total: judgeTotal(for: routine, judge: selectedJudgeForEdit),
                                maxScore: store.template(for: routine).maxScore,
                                isSelected: routine.id == selectedRoutineForEdit?.id
                            ) {
                                selectedRoutineIDForEdit = routine.id
                            }
                        }
                    }
                }
            }
        }
        .padding(20)
        .background(LevitTheme.surface, in: RoundedRectangle(cornerRadius: 22))
        .overlay(RoundedRectangle(cornerRadius: 22).stroke(LevitTheme.cardStroke))
        .shadow(color: .black.opacity(0.045), radius: 22, x: 0, y: 12)
    }

    private func normalizeSelection() {
        if !store.orderedEditableJudges.contains(selectedJudgeForEdit) {
            selectedJudgeForEdit = store.adminScoringJudge ?? store.orderedEditableJudges.first ?? ""
        }
        if !sortedRoutines.contains(where: { $0.id == selectedRoutineIDForEdit }) {
            selectedRoutineIDForEdit = store.selectedRoutine?.id ?? sortedRoutines.first?.id ?? ""
        }
    }

    private func judgeTotal(for routine: Routine, judge: String) -> Double {
        guard !judge.isEmpty else { return 0 }
        let subtotal = store.template(for: routine).criteria.reduce(0) { sum, criterion in
            sum + store.score(for: routine, judge: judge, criterion: criterion)
        }
        return subtotal > 0 ? max(0, subtotal + store.penalty(for: routine, judge: judge)) : 0
    }

    private var driveStatusMessage: String {
        if let message = store.driveExportMessage {
            return message
        }
        if store.hasGoogleDriveConfiguration {
            return "Crea carpetas por bloque, academia y coreografía; sube una hoja de jueceo por juez."
        }
        return "Faltan GOOGLE_CLIENT_ID y GOOGLE_REVERSED_CLIENT_ID para habilitar Drive."
    }

    private var driveStatusColor: Color {
        switch store.driveExportStatus {
        case .idle:
            store.hasGoogleDriveConfiguration ? .green : .orange
        case .exporting:
            .blue
        case .completed:
            .green
        case .failed:
            .red
        }
    }
}

private struct AdminMetricCard: View {
    let icon: String
    let value: String
    let label: String
    let detail: String

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.headline.weight(.bold))
                    .foregroundStyle(LevitTheme.pink)
                    .frame(width: 36, height: 36)
                    .background(LevitTheme.palePink, in: Circle())
                Text(value)
                    .font(.title2.weight(.black))
                    .foregroundStyle(LevitTheme.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(label)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(LevitTheme.muted)
                Text(detail)
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(LevitTheme.muted)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, minHeight: 122, alignment: .leading)
        .background(LevitTheme.solidSurface, in: RoundedRectangle(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(LevitTheme.cardStroke))
    }
}

private struct AdminActionButton: View {
    let title: String
    let icon: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: icon)
                .font(.callout.weight(.black))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .foregroundStyle(LevitTheme.ink)
                .background(LevitTheme.solidSurface, in: RoundedRectangle(cornerRadius: 15))
                .overlay(RoundedRectangle(cornerRadius: 15).stroke(LevitTheme.line))
        }
        .buttonStyle(.plain)
    }
}

private struct AdminMenuField<Content: View>: View {
    let title: String
    let value: String
    let icon: String
    private let content: Content

    init(title: String, value: String, icon: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.value = value
        self.icon = icon
        self.content = content()
    }

    var body: some View {
        Menu {
            content
        } label: {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.headline.weight(.bold))
                    .foregroundStyle(LevitTheme.pink)
                    .frame(width: 38, height: 38)
                    .background(LevitTheme.palePink, in: Circle())
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.caption.weight(.bold))
                        .foregroundStyle(LevitTheme.muted)
                    Text(value)
                        .font(.headline.weight(.black))
                        .foregroundStyle(LevitTheme.ink)
                        .lineLimit(1)
                }
                Spacer()
                Image(systemName: "chevron.down")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(LevitTheme.muted)
            }
            .padding(16)
            .frame(maxWidth: .infinity)
            .background(LevitTheme.solidSurface, in: RoundedRectangle(cornerRadius: 17))
            .overlay(RoundedRectangle(cornerRadius: 17).stroke(LevitTheme.line))
        }
    }
}

private struct AdminSelectedRoutineCard: View {
    let routine: Routine
    let judge: String
    let total: Double
    let maxScore: Double

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 14) {
                Text("#\(routine.id)")
                    .font(.title3.monospacedDigit().weight(.black))
                    .foregroundStyle(LevitTheme.pink)
                    .frame(width: 66, height: 60)
                    .background(LevitTheme.palePink, in: RoundedRectangle(cornerRadius: 15))
                VStack(alignment: .leading, spacing: 4) {
                    Text(routine.name)
                        .font(.headline.weight(.black))
                        .foregroundStyle(LevitTheme.ink)
                        .lineLimit(1)
                    Text(routine.academy)
                        .font(.caption.weight(.bold))
                        .foregroundStyle(LevitTheme.muted)
                        .lineLimit(1)
                }
            }

            HStack(spacing: 6) {
                LevitTag(routine.division)
                LevitTag(routine.category)
                LevitTag(routine.genre)
            }

            Divider().overlay(LevitTheme.line)

            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text(judge.isEmpty ? "Juez" : judge)
                        .font(.caption.weight(.bold))
                        .foregroundStyle(LevitTheme.muted)
                    Text(statusText)
                        .font(.headline.weight(.black))
                        .foregroundStyle(total > 0 ? .green : LevitTheme.ink)
                }
                Spacer()
                Text(total.formatted(.number.precision(.fractionLength(0...1))))
                    .font(.title.weight(.black))
                    .foregroundStyle(LevitTheme.pink)
                Text("/ \(resolvedMax.formatted(.number.precision(.fractionLength(0...1))))")
                    .font(.callout.weight(.black))
                    .foregroundStyle(LevitTheme.muted)
            }
        }
        .padding(18)
        .background(LevitTheme.solidSurface, in: RoundedRectangle(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(LevitTheme.line))
    }

    private var resolvedMax: Double {
        maxScore > 0 ? maxScore : 25
    }

    private var statusText: String {
        total > 0 ? "Con puntaje cargado" : "Pendiente"
    }
}

private struct AdminRoutineEditRow: View {
    let routine: Routine
    let total: Double
    let maxScore: Double
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Text("#\(routine.id)")
                    .font(.callout.monospacedDigit().weight(.black))
                    .foregroundStyle(LevitTheme.pink)
                    .frame(width: 56, height: 46)
                    .background(LevitTheme.palePink, in: RoundedRectangle(cornerRadius: 13))

                VStack(alignment: .leading, spacing: 5) {
                    Text(routine.name)
                        .font(.callout.weight(.black))
                        .foregroundStyle(LevitTheme.ink)
                        .lineLimit(1)
                    HStack(spacing: 7) {
                        Text(routine.academy)
                            .font(.caption.weight(.bold))
                            .foregroundStyle(LevitTheme.muted)
                            .lineLimit(1)
                        LevitTag(routine.division)
                        LevitTag(routine.category)
                        LevitTag(routine.genre)
                    }
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 4) {
                    Text(total > 0 ? "Cargada" : "Pendiente")
                        .font(.caption.weight(.black))
                        .foregroundStyle(total > 0 ? .green : LevitTheme.muted)
                    Text("\(total.formatted(.number.precision(.fractionLength(0...1)))) / \(resolvedMax.formatted(.number.precision(.fractionLength(0...1))))")
                        .font(.callout.monospacedDigit().weight(.black))
                        .foregroundStyle(LevitTheme.ink)
                }

                Image(systemName: isSelected ? "checkmark.circle.fill" : "chevron.right")
                    .font(.headline.weight(.bold))
                    .foregroundStyle(isSelected ? LevitTheme.pink : LevitTheme.muted)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(isSelected ? LevitTheme.palePink : LevitTheme.solidSurface, in: RoundedRectangle(cornerRadius: 17))
            .overlay(RoundedRectangle(cornerRadius: 17).stroke(isSelected ? LevitTheme.pink.opacity(0.32) : LevitTheme.line))
        }
        .buttonStyle(.plain)
    }

    private var resolvedMax: Double {
        maxScore > 0 ? maxScore : 25
    }
}
