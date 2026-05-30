import SwiftUI

struct AdminView: View {
    @EnvironmentObject private var store: JudgingStore
    @Binding var section: AppSection
    let onExportPDF: ([RoutineResult]?, String) -> Void

    @State private var selectedJudgeForEdit = ""
    @State private var selectedRoutineIDForEdit = ""
    @State private var searchText = ""
    @State private var routinePendingDeletion: Routine?
    @State private var isRoutineDeletionAlertPresented = false
    @State private var deleteRoutineImportSecret = ""
    @State private var isDeletingRoutine = false
    @State private var driveFolderName = ""
    @State private var isDriveFolderPromptPresented = false
    @State private var driveFolderPendingOverwrite: String?
    @State private var isDriveOverwriteAlertPresented = false
    @State private var driveFolderErrorMessage: String?
    @State private var isCheckingDriveFolder = false
    @State private var isRefreshingData = false
    @State private var isUpdatingRoutineLevel = false

    private let commonLevelOptions = ["PRINCIPIANTE", "INTERMEDIO", "AVANZADO", "ELITE", "NUDO"]

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
                || routine.level.localizedCaseInsensitiveContains(query)
                || routine.division.localizedCaseInsensitiveContains(query)
                || routine.category.localizedCaseInsensitiveContains(query)
        }
    }

    private var selectedRoutineForEdit: Routine? {
        sortedRoutines.first { $0.id == selectedRoutineIDForEdit } ?? sortedRoutines.first
    }

    private var routineDeletionTitle: String {
        guard let routinePendingDeletion else { return "esta coreografía" }
        return "#\(routinePendingDeletion.id) \(routinePendingDeletion.name)"
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
        .onAppear {
            normalizeSelection()
            prepareDefaultDriveFolderName()
        }
        .onChange(of: store.selectedBlock?.id ?? "") { _, _ in normalizeSelection() }
        .onChange(of: store.judges) { _, _ in normalizeSelection() }
        .onChange(of: store.visibleRoutines) { _, _ in normalizeSelection() }
        .alert("Exportar a Drive", isPresented: $isDriveFolderPromptPresented) {
            TextField("Nombre de carpeta", text: $driveFolderName)
                .textInputAutocapitalization(.words)
                .disableAutocorrection(true)

            Button("Continuar") {
                Task { await prepareDriveExport() }
            }
            .disabled(cleanDriveFolderName.isEmpty || isCheckingDriveFolder || store.driveExportStatus.isExporting)

            Button("Cancelar", role: .cancel) {}
        } message: {
            Text("Elegí el nombre de la carpeta principal donde se van a guardar los PDFs.")
        }
        .alert("Carpeta existente", isPresented: $isDriveOverwriteAlertPresented) {
            Button("Exportar igual") {
                guard let folderName = driveFolderPendingOverwrite else { return }
                Task { await exportDrive(named: folderName) }
            }
            Button("Cancelar", role: .cancel) {
                resetPendingDriveOverwrite()
            }
        } message: {
            Text("La carpeta \(driveFolderPendingOverwrite ?? "") ya existe en Drive. Los PDFs con el mismo nombre se van a actualizar.")
        }
        .alert("No se pudo revisar Drive", isPresented: Binding(
            get: { driveFolderErrorMessage != nil },
            set: { if !$0 { driveFolderErrorMessage = nil } }
        )) {
            Button("OK", role: .cancel) {
                driveFolderErrorMessage = nil
            }
        } message: {
            Text(driveFolderErrorMessage ?? "")
        }
        .alert("Borrar coreografía", isPresented: $isRoutineDeletionAlertPresented) {
            SecureField("Clave de importación", text: $deleteRoutineImportSecret)
                .textInputAutocapitalization(.never)
                .disableAutocorrection(true)

            Button("Borrar", role: .destructive) {
                guard let routine = routinePendingDeletion else { return }
                let secret = deleteRoutineImportSecret
                Task { await deletePendingRoutine(routine, importSecret: secret) }
            }
            .disabled(deleteRoutineImportSecret.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isDeletingRoutine)

            Button("Cancelar", role: .cancel) {
                resetPendingRoutineDeletion()
            }
        } message: {
            Text("Se va a borrar \(routineDeletionTitle) de \(currentEventTitle). También se quitarán sus puntajes, devoluciones, penalizaciones y favoritos.")
        }
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
                Task { await refreshAdminData() }
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
                presentDriveFolderPrompt()
            } label: {
                Label("Exportar a Drive", systemImage: "icloud.and.arrow.up")
                    .font(.callout.weight(.black))
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .foregroundStyle(.white)
                    .background(LevitTheme.pinkGradient, in: RoundedRectangle(cornerRadius: 14))
                    .contentShape(RoundedRectangle(cornerRadius: 14))
            }
            .buttonStyle(.plain)
            .disabled(store.driveExportStatus.isExporting || isCheckingDriveFolder)
            .opacity(store.driveExportStatus.isExporting || isCheckingDriveFolder ? 0.58 : 1)
        }
        .padding(18)
        .background(LevitTheme.elevatedSurface, in: RoundedRectangle(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(LevitTheme.line))
    }

    private var editAsJudgePanel: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top, spacing: 18) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(editAsJudgeTitle)
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
                    AdminMenuField(
                        title: "Juez",
                        value: selectedJudgeForEdit.isEmpty ? "Sin jueces" : selectedJudgeForEdit,
                        icon: "person.fill",
                        optionSections: judgeMenuOptions
                    )

                    AdminMenuField(
                        title: "Bloque",
                        value: store.selectedBlock?.name ?? "Sin bloques",
                        icon: "square.stack.3d.up.fill",
                        optionSections: blockMenuOptions
                    )

                    if let routine = selectedRoutineForEdit {
                        AdminSelectedRoutineCard(
                            routine: routine,
                            judge: selectedJudgeForEdit,
                            total: judgeTotal(for: routine, judge: selectedJudgeForEdit),
                            maxScore: store.template(for: routine).maxScore
                        )

                        routineLevelEditor(for: routine)

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
                                .contentShape(RoundedRectangle(cornerRadius: 16))
                        }
                        .buttonStyle(.plain)
                        .disabled(selectedJudgeForEdit.isEmpty)
                        .opacity(selectedJudgeForEdit.isEmpty ? 0.45 : 1)
                    }
                }
                .frame(width: 340)

                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 12) {
                        Label("Coreografías de \(store.selectedBlock?.name ?? "bloque")", systemImage: "list.bullet.rectangle")
                            .font(.headline.weight(.black))
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                        Spacer()
                        RefreshDataButton(isRefreshing: isRefreshingData) {
                            Task { await refreshAdminData() }
                        }
                        .disabled(store.isLoadingBackendData)
                        .opacity(store.isLoadingBackendData ? 0.58 : 1)
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
                                isSelected: routine.id == selectedRoutineForEdit?.id,
                                onDelete: {
                                    routinePendingDeletion = routine
                                    deleteRoutineImportSecret = ""
                                    isRoutineDeletionAlertPresented = true
                                }
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

    private func selectAdminBlock(_ block: DanceBlock) {
        store.selectBlock(block)
        searchText = ""
        normalizeSelection()
    }

    private func routineLevelEditor(for routine: Routine) -> some View {
        AdminMenuField(
            title: "Nivel",
            value: displayLevel(routine.level),
            icon: "slider.horizontal.3",
            optionSections: routineLevelMenuOptions(for: routine)
        )
        .disabled(isUpdatingRoutineLevel || !store.hasRemoteConfiguration)
        .opacity(isUpdatingRoutineLevel || !store.hasRemoteConfiguration ? 0.58 : 1)
    }

    private var judgeMenuOptions: [[AdminDropdownOption]] {
        let options = store.orderedEditableJudges.map { judge in
            AdminDropdownOption(
                id: judge.normalizedKey,
                title: judge,
                icon: "person.fill",
                isSelected: judge == selectedJudgeForEdit
            ) {
                selectedJudgeForEdit = judge
            }
        }
        return [options.isEmpty ? [
            AdminDropdownOption(id: "empty", title: "Sin jueces", icon: "exclamationmark.circle", isEnabled: false) {}
        ] : options]
    }

    private var blockMenuOptions: [[AdminDropdownOption]] {
        let options = store.blocks.map { block in
            AdminDropdownOption(
                id: block.id,
                title: block.name,
                icon: "square.stack.3d.up.fill",
                isSelected: block.id == store.selectedBlock?.id
            ) {
                selectAdminBlock(block)
            }
        }
        return [options.isEmpty ? [
            AdminDropdownOption(id: "empty", title: "Sin bloques", icon: "exclamationmark.circle", isEnabled: false) {}
        ] : options]
    }

    private func routineLevelMenuOptions(for routine: Routine) -> [[AdminDropdownOption]] {
        let currentLevel = normalizedLevelKey(routine.level)
        let levelOptions = routineLevelOptions.map { level in
            AdminDropdownOption(
                id: level.normalizedKey,
                title: level,
                icon: "slider.horizontal.3",
                isSelected: currentLevel == normalizedLevelKey(level)
            ) {
                Task { await updateRoutineLevel(routine, to: level) }
            }
        }

        return [levelOptions]
    }

    @MainActor
    private func refreshAdminData() async {
        guard !isRefreshingData else { return }
        isRefreshingData = true
        defer {
            isRefreshingData = false
            normalizeSelection()
        }

        do {
            try await store.refreshCurrentEvent()
            store.showOperationSuccess("Datos actualizados", message: "Se volvieron a traer las coreografías y puntajes del programa actual.")
        } catch {
            store.showOperationFailure("No se pudo actualizar", message: error.localizedDescription)
        }
    }

    private func normalizeSelection() {
        if !store.orderedEditableJudges.contains(selectedJudgeForEdit) {
            selectedJudgeForEdit = store.adminScoringJudge ?? store.orderedEditableJudges.first ?? ""
        }
        if !sortedRoutines.contains(where: { $0.id == selectedRoutineIDForEdit }) {
            selectedRoutineIDForEdit = store.selectedRoutine?.id ?? sortedRoutines.first?.id ?? ""
        }
    }

    private var editAsJudgeTitle: String {
        selectedJudgeForEdit.isEmpty ? "Editar como juez" : "Editar como \(selectedJudgeForEdit)"
    }

    @MainActor
    private func deletePendingRoutine(_ routine: Routine, importSecret: String) async {
        let routineTitle = "#\(routine.id) \(routine.name)"
        isDeletingRoutine = true
        defer { isDeletingRoutine = false }

        do {
            try await store.deleteRoutine(routine, importSecret: importSecret)
            resetPendingRoutineDeletion()
            normalizeSelection()
            store.showOperationSuccess("Coreografía borrada", message: "\(routineTitle) se borró del programa actual.")
        } catch {
            resetPendingRoutineDeletion()
            store.showOperationFailure("No se pudo borrar coreografía", message: error.localizedDescription)
        }
    }

    private func resetPendingRoutineDeletion() {
        isRoutineDeletionAlertPresented = false
        routinePendingDeletion = nil
        deleteRoutineImportSecret = ""
    }

    @MainActor
    private func updateRoutineLevel(_ routine: Routine, to level: String) async {
        let cleanLevel = cleanLevelValue(level)
        guard normalizedLevelKey(routine.level) != normalizedLevelKey(cleanLevel) else { return }
        guard !isUpdatingRoutineLevel else { return }

        isUpdatingRoutineLevel = true
        defer { isUpdatingRoutineLevel = false }

        do {
            try await store.updateRoutineLevel(routine, level: cleanLevel)
            normalizeSelection()
            store.showOperationSuccess(
                "Nivel actualizado",
                message: "#\(routine.id) \(routine.name) ahora está en \(displayLevel(cleanLevel))."
            )
        } catch {
            store.showOperationFailure("No se pudo cambiar el nivel", message: error.localizedDescription)
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

    private var cleanDriveFolderName: String {
        driveFolderName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func prepareDefaultDriveFolderName() {
        guard cleanDriveFolderName.isEmpty else { return }
        driveFolderName = store.defaultDriveRootFolderName
    }

    private func presentDriveFolderPrompt() {
        guard !store.driveExportStatus.isExporting, !isCheckingDriveFolder else { return }
        prepareDefaultDriveFolderName()
        isDriveFolderPromptPresented = true
    }

    @MainActor
    private func prepareDriveExport() async {
        let folderName = cleanDriveFolderName
        guard !folderName.isEmpty else { return }

        isCheckingDriveFolder = true
        do {
            let exists = try await store.driveFolderExists(named: folderName)
            isCheckingDriveFolder = false
            if exists {
                driveFolderPendingOverwrite = folderName
                isDriveOverwriteAlertPresented = true
            } else {
                await exportDrive(named: folderName)
            }
        } catch {
            isCheckingDriveFolder = false
            driveFolderErrorMessage = error.localizedDescription
        }
    }

    @MainActor
    private func exportDrive(named folderName: String) async {
        resetPendingDriveOverwrite()
        await store.exportSelectedBlockToDrive(rootFolderName: folderName)
    }

    private func resetPendingDriveOverwrite() {
        isDriveOverwriteAlertPresented = false
        driveFolderPendingOverwrite = nil
    }

    private var routineLevelOptions: [String] {
        let commonKeys = Set(commonLevelOptions.map(\.normalizedKey))
        var seen = Set<String>()
        var options = commonLevelOptions.filter { level in
            seen.insert(level.normalizedKey).inserted
        }
        let extraLevels = store.routines
            .map { cleanLevelValue($0.level) }
            .filter { !$0.isEmpty && !commonKeys.contains($0.normalizedKey) }
            .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }

        for level in extraLevels where seen.insert(level.normalizedKey).inserted {
            options.append(level)
        }
        return options
    }

    private func cleanLevelValue(_ level: String) -> String {
        let trimmed = level.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed == "-" ? "" : trimmed
    }

    private func displayLevel(_ level: String) -> String {
        let cleanLevel = cleanLevelValue(level)
        return cleanLevel.isEmpty ? "Sin nivel" : cleanLevel
    }

    private func normalizedLevelKey(_ level: String) -> String {
        cleanLevelValue(level).normalizedKey
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
                .contentShape(RoundedRectangle(cornerRadius: 15))
        }
        .buttonStyle(.plain)
    }
}

private struct AdminDropdownOption: Identifiable {
    let id: String
    let title: String
    let icon: String
    let isSelected: Bool
    let isEnabled: Bool
    let action: () -> Void

    init(
        id: String,
        title: String,
        icon: String,
        isSelected: Bool = false,
        isEnabled: Bool = true,
        action: @escaping () -> Void
    ) {
        self.id = id
        self.title = title
        self.icon = icon
        self.isSelected = isSelected
        self.isEnabled = isEnabled
        self.action = action
    }
}

private struct AdminMenuField: View {
    let title: String
    let value: String
    let icon: String
    let optionSections: [[AdminDropdownOption]]

    @State private var isPresented = false

    var body: some View {
        Button {
            guard hasEnabledOptions else { return }
            isPresented.toggle()
        } label: {
            label
        }
        .buttonStyle(.plain)
        .disabled(!hasEnabledOptions)
        .opacity(hasEnabledOptions ? 1 : 0.58)
        .popover(isPresented: $isPresented, arrowEdge: .bottom) {
            dropdownContent
        }
    }

    private var label: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.headline.weight(.black))
                .foregroundStyle(LevitTheme.pink)
                .frame(width: 42, height: 42)
                .background(LevitTheme.palePink, in: RoundedRectangle(cornerRadius: 12, style: .continuous))

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.caption.weight(.black))
                    .foregroundStyle(LevitTheme.muted)
                    .lineLimit(1)
                Text(value)
                    .font(.headline.weight(.black))
                    .foregroundStyle(LevitTheme.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.74)
            }

            Spacer(minLength: 8)

            Image(systemName: isPresented ? "chevron.up" : "chevron.down")
                .font(.caption.weight(.black))
                .foregroundStyle(LevitTheme.ink)
                .frame(width: 34, height: 34)
                .background(LevitTheme.softFill, in: Circle())
        }
        .padding(12)
        .frame(maxWidth: .infinity, minHeight: 66)
        .background(LevitTheme.solidSurface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(LevitTheme.line))
        .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var dropdownContent: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(optionSections.enumerated()), id: \.offset) { sectionIndex, options in
                if sectionIndex > 0 {
                    Divider()
                        .overlay(LevitTheme.line)
                        .padding(.vertical, 3)
                }

                ForEach(options) { option in
                    optionRow(option)
                }
            }
        }
        .padding(8)
        .frame(width: 306, alignment: .topLeading)
        .background(LevitTheme.surface)
        #if os(iOS)
        .presentationCompactAdaptation(.popover)
        #endif
    }

    private func optionRow(_ option: AdminDropdownOption) -> some View {
        Button {
            guard option.isEnabled else { return }
            isPresented = false
            option.action()
        } label: {
            HStack(spacing: 10) {
                Image(systemName: option.isSelected ? "checkmark.circle.fill" : option.icon)
                    .font(.callout.weight(.black))
                    .foregroundStyle(option.isSelected ? LevitTheme.pink : LevitTheme.muted)
                    .frame(width: 24)

                Text(option.title)
                    .font(.callout.weight(.black))
                    .foregroundStyle(option.isEnabled ? LevitTheme.ink : LevitTheme.muted)
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)

                Spacer()
            }
            .padding(.horizontal, 11)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(option.isSelected ? LevitTheme.palePink : Color.clear, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(!option.isEnabled)
    }

    private var hasEnabledOptions: Bool {
        optionSections.flatMap { $0 }.contains { $0.isEnabled }
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
                if !cleanLevel.isEmpty {
                    LevitTag(cleanLevel)
                }
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

    private var cleanLevel: String {
        let trimmed = routine.level.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed == "-" ? "" : trimmed
    }
}

private struct AdminRoutineEditRow: View {
    let routine: Routine
    let total: Double
    let maxScore: Double
    let isSelected: Bool
    let onDelete: (() -> Void)?
    let action: () -> Void

    var body: some View {
        HStack(spacing: 0) {
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
                            if !cleanLevel.isEmpty {
                                LevitTag(cleanLevel)
                            }
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
                .padding(.leading, 14)
                .padding(.trailing, onDelete == nil ? 14 : 10)
                .padding(.vertical, 12)
                .frame(maxWidth: .infinity, minHeight: 70, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Seleccionar coreografía \(routine.name)")

            if let onDelete {
                Button(role: .destructive, action: onDelete) {
                    Image(systemName: "trash")
                        .font(.headline.weight(.bold))
                        .frame(width: 42, height: 42)
                        .foregroundStyle(.red)
                        .background(Color.red.opacity(0.10), in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Borrar coreografía \(routine.name)")
                .padding(.trailing, 14)
            }
        }
        .background(isSelected ? LevitTheme.palePink : LevitTheme.solidSurface, in: RoundedRectangle(cornerRadius: 17))
        .overlay(RoundedRectangle(cornerRadius: 17).stroke(isSelected ? LevitTheme.pink.opacity(0.32) : LevitTheme.line))
    }

    private var resolvedMax: Double {
        maxScore > 0 ? maxScore : 25
    }

    private var cleanLevel: String {
        let trimmed = routine.level.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed == "-" ? "" : trimmed
    }
}
