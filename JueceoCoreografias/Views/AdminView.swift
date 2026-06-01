import SwiftUI
import JueceoCore

private let judgeActivityPollingIntervalNanoseconds: UInt64 = 10_000_000_000

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
        .onChange(of: store.selectedBlock?.id ?? "") { _, _ in
            normalizeSelection()
        }
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
            AdminMetricCard(icon: "person.3.fill", value: "\(store.editableJudges.count)", label: "Jueces", detail: "Admin configura")
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

struct ScoreEditorView: View {
    @EnvironmentObject private var store: JudgingStore
    @Binding var section: AppSection

    @State private var searchText = ""
    @State private var isRefreshingData = false
    @State private var driveFolderName = ""
    @State private var isDriveFolderPromptPresented = false
    @State private var driveFolderPendingOverwrite: String?
    @State private var isDriveOverwriteAlertPresented = false
    @State private var driveFolderErrorMessage: String?
    @State private var isCheckingDriveFolder = false
    @State private var routineMetadataUpdateKey: String?

    private let minimumRoutineColumnWidth: CGFloat = 560
    private let judgeColumnWidth: CGFloat = 178
    private let totalColumnWidth: CGFloat = 178
    private let scoreEditorHeaderHeight: CGFloat = 74
    private let scoreEditorRowHeight: CGFloat = 116
    private let scoreEditorEmptyRowHeight: CGFloat = 96

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
                || routine.state.localizedCaseInsensitiveContains(query)
        }
    }

    private var editableJudges: [String] {
        let judgesByKey = Dictionary(
            uniqueKeysWithValues: store.orderedEditableJudges.map { ($0.normalizedKey, $0) }
        )
        return allowedJudgeNames.compactMap { judgesByKey[$0.normalizedKey] }
    }

    private var allowedJudgeNames: [String] {
        AppBrand.competition.adminScoringJudgeNames(for: store.selectedBlock)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                driveExportPanel
                editorPanel
            }
            .padding(.horizontal, 34)
            .padding(.vertical, 28)
            .frame(maxWidth: 1360, alignment: .leading)
        }
        .background(LevitTheme.paper.ignoresSafeArea())
        .foregroundStyle(LevitTheme.ink)
        .onAppear {
            prepareDefaultDriveFolderName()
        }
        .task {
            await pollJudgeActivity()
        }
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
    }

    private var driveExportPanel: some View {
        HStack(alignment: .center, spacing: 16) {
            ZStack {
                Circle()
                    .fill(driveStatusColor.opacity(0.15))
                    .frame(width: 52, height: 52)
                if store.driveExportStatus.isExporting {
                    ProgressView()
                        .tint(LevitTheme.pink)
                } else {
                    Image(systemName: store.driveExportStatus.systemImage)
                        .font(.title3.weight(.black))
                        .foregroundStyle(driveStatusColor)
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(store.driveExportStatus.title)
                    .font(.title3.weight(.black))
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
                    .font(.headline.weight(.black))
                    .lineLimit(1)
                    .minimumScaleFactor(0.74)
                    .padding(.horizontal, 22)
                    .padding(.vertical, 16)
                    .foregroundStyle(.white)
                    .background(LevitTheme.pinkGradient, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            .buttonStyle(.plain)
            .disabled(store.driveExportStatus.isExporting || isCheckingDriveFolder)
            .opacity(store.driveExportStatus.isExporting || isCheckingDriveFolder ? 0.58 : 1)
        }
        .padding(20)
        .background(
            LinearGradient(
                colors: [
                    LevitTheme.elevatedSurface,
                    LevitTheme.darkPanel2.opacity(0.78)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(cornerRadius: 18, style: .continuous)
        )
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(LevitTheme.line))
    }

    private var editorPanel: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .center, spacing: 14) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Editar calificaciones")
                        .font(.system(size: 30, weight: .black, design: .rounded))
                        .foregroundStyle(LevitTheme.ink)
                    Text("Revisa y edita las coreografías por cada juez. Los totales se actualizan automáticamente.")
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(LevitTheme.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 20)

                ScoreEditorBlockMenu()
                    .frame(width: 176)

                searchField
                    .frame(width: 260)

                RefreshDataButton(isRefreshing: isRefreshingData) {
                    Task { await refreshAdminData() }
                }
                .disabled(store.isLoadingBackendData)
                .opacity(store.isLoadingBackendData ? 0.58 : 1)
            }

            if editableJudges.isEmpty {
                emptyState
            } else {
                scoresTable
            }
        }
        .padding(22)
        .background(LevitTheme.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(LevitTheme.cardStroke))
        .shadow(color: .black.opacity(0.055), radius: 24, x: 0, y: 12)
    }

    private var searchField: some View {
        HStack(spacing: 9) {
            Image(systemName: "magnifyingglass")
                .font(.callout.weight(.bold))
                .foregroundStyle(LevitTheme.muted)
            TextField("Buscar coreografía...", text: $searchText)
                .textInputAutocapitalization(.never)
                .disableAutocorrection(true)
        }
        .font(.callout.weight(.semibold))
        .padding(.horizontal, 14)
        .padding(.vertical, 13)
        .background(LevitTheme.softFill, in: RoundedRectangle(cornerRadius: 13, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 13, style: .continuous).stroke(LevitTheme.line))
    }

    private var scoresTable: some View {
        let judges = editableJudges
        let height = scoreEditorHeaderHeight + (filteredRoutines.isEmpty ? scoreEditorEmptyRowHeight : CGFloat(filteredRoutines.count) * scoreEditorRowHeight)

        return GeometryReader { proxy in
            let metrics = scoreTableMetrics(availableWidth: proxy.size.width, judgeCount: judges.count)

            ScrollView(.horizontal, showsIndicators: metrics.tableWidth > proxy.size.width + 1) {
                VStack(spacing: 0) {
                    ScoreEditorHeaderRow(
                        judges: judges,
                        routineColumnWidth: metrics.routineColumnWidth,
                        judgeColumnWidth: judgeColumnWidth,
                        totalColumnWidth: totalColumnWidth
                    )

                    if filteredRoutines.isEmpty {
                        noResultsRow(width: metrics.tableWidth)
                    } else {
                        ForEach(filteredRoutines) { routine in
                            ScoreEditorRoutineRow(
                                routine: routine,
                                judges: judges,
                                routineColumnWidth: metrics.routineColumnWidth,
                                judgeColumnWidth: judgeColumnWidth,
                                totalColumnWidth: totalColumnWidth,
                                judgeScore: { judge in judgeScore(for: routine, judge: judge) },
                                totalScore: totalScore(for: routine, judges: judges),
                                totalMaxScore: store.template(for: routine).maxScore * Double(judges.count),
                                metadataOptions: { field in routineMetadataOptions(for: field, routine: routine) },
                                isMetadataUpdating: routineMetadataUpdateKey?.hasPrefix("\(routine.id)::") == true,
                                updateMetadata: { field, value in
                                    Task { await updateRoutineMetadata(routine, field: field, value: value) }
                                },
                                openJudgeSheet: { judge in openJudgeSheet(routine: routine, judge: judge) }
                            )
                        }
                    }
                }
                .frame(width: metrics.tableWidth, alignment: .leading)
                .background(LevitTheme.darkPanel.opacity(0.24), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(LevitTheme.line))
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
        }
        .frame(height: height)
    }

    private func scoreTableMetrics(availableWidth: CGFloat, judgeCount: Int) -> (routineColumnWidth: CGFloat, tableWidth: CGFloat) {
        let fixedWidth = totalColumnWidth + CGFloat(judgeCount) * judgeColumnWidth
        let routineWidth = max(minimumRoutineColumnWidth, availableWidth - fixedWidth)
        let tableWidth = max(availableWidth, fixedWidth + routineWidth)
        return (routineWidth, tableWidth)
    }

    private var emptyState: some View {
        VStack(alignment: .center, spacing: 10) {
            Image(systemName: "person.crop.circle.badge.exclamationmark")
                .font(.system(size: 32, weight: .bold))
                .foregroundStyle(LevitTheme.pink)
            Text("Sin jueces para editar")
                .font(.headline.weight(.black))
                .foregroundStyle(LevitTheme.ink)
            Text("Agregá jueces al programa para poder cargar o corregir calificaciones.")
                .font(.callout.weight(.semibold))
                .foregroundStyle(LevitTheme.muted)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 46)
        .background(LevitTheme.softFill, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func noResultsRow(width: CGFloat) -> some View {
        Text("No hay coreografías que coincidan con la búsqueda.")
            .font(.callout.weight(.semibold))
            .foregroundStyle(LevitTheme.muted)
            .frame(width: width, height: 96)
            .background(LevitTheme.softFill.opacity(0.5))
    }

    private func openJudgeSheet(routine: Routine, judge: String) {
        guard !judge.isEmpty else { return }
        store.beginAdminScoring(judge: judge, routine: routine)
        section = .jueceo
    }

    private func routineMetadataOptions(for field: RoutineMetadataField, routine: Routine) -> [String] {
        let currentValue = cleanRoutineMetadataValue(field.value(in: routine))
        let rawValues: [String]
        switch field {
        case .division:
            rawValues = store.routines.map(\.division)
        case .level:
            rawValues = ["PRINCIPIANTE", "INTERMEDIO", "AVANZADO", "ELITE", "NUDO"] + store.routines.map(\.level)
        case .category:
            rawValues = store.routines.map(\.category)
        case .genre:
            rawValues = store.routines.map(\.genre)
        }

        var seen = Set<String>()
        var options: [String] = []
        for value in ([currentValue] + rawValues) {
            let cleanValue = cleanRoutineMetadataValue(value)
            guard !cleanValue.isEmpty else { continue }
            guard seen.insert(cleanValue.normalizedKey).inserted else { continue }
            options.append(cleanValue)
        }

        if field == .level {
            let priority = ["PRINCIPIANTE", "INTERMEDIO", "AVANZADO", "ELITE", "NUDO"]
            return options.sorted { lhs, rhs in
                let lhsIndex = priority.firstIndex { $0.normalizedKey == lhs.normalizedKey } ?? Int.max
                let rhsIndex = priority.firstIndex { $0.normalizedKey == rhs.normalizedKey } ?? Int.max
                if lhsIndex != rhsIndex {
                    return lhsIndex < rhsIndex
                }
                return lhs.localizedCaseInsensitiveCompare(rhs) == .orderedAscending
            }
        }

        return options.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    @MainActor
    private func updateRoutineMetadata(_ routine: Routine, field: RoutineMetadataField, value: String) async {
        let cleanValue = cleanRoutineMetadataValue(value)
        let currentValue = cleanRoutineMetadataValue(field.value(in: routine))
        guard currentValue.normalizedKey != cleanValue.normalizedKey else { return }
        guard routineMetadataUpdateKey == nil else { return }

        routineMetadataUpdateKey = "\(routine.id)::\(field.rawValue)"
        defer { routineMetadataUpdateKey = nil }

        do {
            try await store.updateRoutineMetadata(routine, field: field, value: cleanValue)
            store.showOperationSuccess(
                "Coreografía actualizada",
                message: "#\(routine.id) \(routine.name): \(field.title) ahora es \(cleanValue)."
            )
        } catch {
            store.showOperationFailure("No se pudo editar coreografía", message: error.localizedDescription)
        }
    }

    private func cleanRoutineMetadataValue(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed == "-" || trimmed.normalizedKey == "SIN NIVEL" ? "" : trimmed
    }

    @MainActor
    private func refreshAdminData() async {
        guard !isRefreshingData else { return }
        isRefreshingData = true
        defer { isRefreshingData = false }

        do {
            try await store.refreshCurrentEvent()
            await store.refreshJudgeActivity()
            store.showOperationSuccess("Datos actualizados", message: "Se volvieron a traer las coreografías y puntajes del programa actual.")
        } catch {
            store.showOperationFailure("No se pudo actualizar", message: error.localizedDescription)
        }
    }

    private func judgeScore(for routine: Routine, judge: String) -> ScoreEditorJudgeScore {
        let template = store.template(for: routine)
        let values = template.criteria.map { store.score(for: routine, judge: judge, criterion: $0) }
        let subtotal = values.reduce(0, +)
        let hasAnyScore = values.contains { $0 > 0 }
        let isComplete = !values.isEmpty && values.allSatisfy { $0 > 0 }
        let total = hasAnyScore ? max(0, subtotal + store.penalty(for: routine, judge: judge)) : 0
        return ScoreEditorJudgeScore(
            judge: judge,
            total: total,
            maxScore: template.maxScore,
            isComplete: isComplete,
            hasAnyScore: hasAnyScore,
            isCurrentlyScoring: isJudgeCurrentlyScoring(routine: routine, judge: judge)
        )
    }

    private func isJudgeCurrentlyScoring(routine: Routine, judge: String) -> Bool {
        store.latestJudgeActivities.contains { activity in
            let matchesJudge = activity.judgeID == judge.stableRemoteID
                || activity.judgeName.normalizedKey == judge.normalizedKey
            let matchesRoutine = activity.routine?.id == routine.id
                || activity.routineID == routine.id
            return matchesJudge
                && matchesRoutine
                && activity.state == .viewingSheet
                && !activity.isInactive()
        }
    }

    private func pollJudgeActivity() async {
        await store.refreshJudgeActivity()
        while !Task.isCancelled {
            try? await Task.sleep(nanoseconds: judgeActivityPollingIntervalNanoseconds)
            await store.refreshJudgeActivity()
        }
    }

    private func totalScore(for routine: Routine, judges: [String]) -> Double {
        judges.reduce(0) { sum, judge in
            sum + judgeScore(for: routine, judge: judge).total
        }
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

private struct ScoreEditorJudgeScore {
    let judge: String
    let total: Double
    let maxScore: Double
    let isComplete: Bool
    let hasAnyScore: Bool
    let isCurrentlyScoring: Bool
}

private struct ScoreEditorBlockMenu: View {
    @EnvironmentObject private var store: JudgingStore

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
            HStack(spacing: 9) {
                Image(systemName: "list.bullet.rectangle")
                    .font(.callout.weight(.black))
                    .foregroundStyle(LevitTheme.muted)
                Text(store.selectedBlock?.name.uppercased() ?? "BLOQUE")
                    .font(.callout.weight(.black))
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
                Image(systemName: "chevron.down")
                    .font(.caption.weight(.black))
                    .foregroundStyle(LevitTheme.muted)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 13)
            .foregroundStyle(LevitTheme.ink)
            .background(LevitTheme.softFill, in: RoundedRectangle(cornerRadius: 13, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 13, style: .continuous).stroke(LevitTheme.line))
            .contentShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

private struct ScoreEditorHeaderRow: View {
    let judges: [String]
    let routineColumnWidth: CGFloat
    let judgeColumnWidth: CGFloat
    let totalColumnWidth: CGFloat

    var body: some View {
        HStack(spacing: 0) {
            headerCell(width: routineColumnWidth, alignment: .leading) {
                HStack(spacing: 6) {
                    Text("Coreografía")
                    Image(systemName: "arrow.up.arrow.down")
                        .font(.caption2.weight(.black))
                }
            }

            ForEach(judges, id: \.self) { judge in
                headerCell(width: judgeColumnWidth, alignment: .center) {
                    VStack(spacing: 2) {
                        Text(judge.capitalized)
                            .font(.headline.weight(.black))
                            .foregroundStyle(LevitTheme.ink)
                        Text("Juez")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(LevitTheme.muted)
                    }
                }
            }

            headerCell(width: totalColumnWidth, alignment: .center) {
                VStack(spacing: 2) {
                    Text("Total")
                        .font(.headline.weight(.black))
                        .foregroundStyle(LevitTheme.ink)
                    Text("(\(judges.count) jueces)")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(LevitTheme.muted)
                }
            }
        }
        .frame(height: 74)
        .background(LevitTheme.softFill.opacity(0.45))
    }

    private func headerCell<Content: View>(
        width: CGFloat,
        alignment: Alignment,
        @ViewBuilder content: () -> Content
    ) -> some View {
        content()
            .font(.caption.weight(.black))
            .textCase(.uppercase)
            .foregroundStyle(LevitTheme.muted)
            .frame(maxWidth: .infinity, alignment: alignment)
            .padding(.horizontal, alignment == .leading ? 34 : 12)
            .frame(width: width, height: 74, alignment: alignment)
            .overlay(alignment: .trailing) {
                Rectangle()
                    .fill(LevitTheme.line)
                    .frame(width: 1)
            }
    }
}

private struct ScoreEditorRoutineRow: View {
    let routine: Routine
    let judges: [String]
    let routineColumnWidth: CGFloat
    let judgeColumnWidth: CGFloat
    let totalColumnWidth: CGFloat
    let judgeScore: (String) -> ScoreEditorJudgeScore
    let totalScore: Double
    let totalMaxScore: Double
    let metadataOptions: (RoutineMetadataField) -> [String]
    let isMetadataUpdating: Bool
    let updateMetadata: (RoutineMetadataField, String) -> Void
    let openJudgeSheet: (String) -> Void

    var body: some View {
        HStack(spacing: 0) {
            routineCell

            ForEach(judges, id: \.self) { judge in
                Button {
                    openJudgeSheet(judge)
                } label: {
                    judgeCell(judgeScore(judge))
                }
                .buttonStyle(.plain)
            }

            totalCell
        }
        .frame(height: 116)
        .background(rowBackground)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(LevitTheme.line)
                .frame(height: 1)
        }
    }

    private var routineCell: some View {
        HStack(spacing: 14) {
            Button {
                openFirstJudgeSheet()
            } label: {
                Text("#\(routine.id)")
                    .font(.title3.weight(.black))
                    .foregroundStyle(LevitTheme.pink)
                    .frame(width: 58, height: 48)
                    .background(LevitTheme.palePink, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 8) {
                Button {
                    openFirstJudgeSheet()
                } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(routine.name)
                            .font(.headline.weight(.black))
                            .foregroundStyle(LevitTheme.ink)
                            .lineLimit(1)
                            .minimumScaleFactor(0.75)

                        Text(routine.academy.uppercased())
                            .font(.caption.weight(.black))
                            .foregroundStyle(LevitTheme.muted)
                            .lineLimit(1)
                    }
                }
                .buttonStyle(.plain)

                HStack(spacing: 7) {
                    ForEach(RoutineMetadataField.allCases) { field in
                        let value = displayMetadataValue(field.value(in: routine), field: field)
                        if !value.isEmpty {
                            ScoreEditorMetadataPill(
                                title: field.title,
                                value: value,
                                systemImage: field.systemImage,
                                options: metadataOptions(field),
                                isEnabled: !isMetadataUpdating,
                                onSelect: { selectedValue in updateMetadata(field, selectedValue) }
                            )
                        }
                    }
                }
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 34)
        .frame(width: routineColumnWidth, height: 116, alignment: .leading)
        .contentShape(Rectangle())
        .overlay(alignment: .trailing) {
            Rectangle()
                .fill(LevitTheme.line)
                .frame(width: 1)
        }
    }

    private func openFirstJudgeSheet() {
        if let judge = judges.first {
            openJudgeSheet(judge)
        }
    }

    private func displayMetadataValue(_ value: String, field: RoutineMetadataField) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if field == .level, (trimmed.isEmpty || trimmed == "-" || trimmed.normalizedKey == "SIN NIVEL") {
            return ""
        }
        return trimmed
    }

    private func judgeCell(_ score: ScoreEditorJudgeScore) -> some View {
        VStack(spacing: 7) {
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(score.hasAnyScore ? scoreText(score.total) : "-")
                    .font(.title3.weight(.black))
                    .foregroundStyle(LevitTheme.ink)
                Text("/\(scoreText(score.maxScore))")
                    .font(.headline.weight(.black))
                    .foregroundStyle(LevitTheme.muted)
            }

            HStack(spacing: 5) {
                statusIndicator(for: score)
                Text(statusText(for: score))
                    .font(.caption.weight(.bold))
                    .foregroundStyle(score.isCurrentlyScoring || score.isComplete ? LevitTheme.ink : LevitTheme.muted)
            }
        }
        .frame(width: judgeColumnWidth, height: 116)
        .contentShape(Rectangle())
        .overlay(alignment: .trailing) {
            Rectangle()
                .fill(LevitTheme.line)
                .frame(width: 1)
        }
    }

    private var totalCell: some View {
        let progress = totalMaxScore > 0 ? min(max(totalScore / totalMaxScore, 0), 1) : 0

        return VStack(spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(scoreText(totalScore))
                    .font(.system(size: 28, weight: .black, design: .rounded))
                    .foregroundStyle(LevitTheme.pink)
                Text("/\(scoreText(totalMaxScore))")
                    .font(.headline.weight(.black))
                    .foregroundStyle(LevitTheme.muted)
            }

            Text("\(Int((progress * 100).rounded()))%")
                .font(.caption.weight(.bold))
                .foregroundStyle(LevitTheme.muted)

            ProgressView(value: progress)
                .tint(LevitTheme.pink)
                .frame(width: 104)
        }
        .frame(width: totalColumnWidth, height: 116)
    }

    private var rowBackground: some ShapeStyle {
        totalScore > 0 ? LevitTheme.palePink.opacity(0.65) : LevitTheme.softFill.opacity(0.34)
    }

    @ViewBuilder
    private func statusIndicator(for score: ScoreEditorJudgeScore) -> some View {
        if score.isCurrentlyScoring {
            ProgressView()
                .controlSize(.small)
                .tint(LevitTheme.pink)
        } else {
            Image(systemName: score.isComplete ? "checkmark.circle.fill" : "circle")
                .font(.caption.weight(.black))
                .foregroundStyle(score.isComplete ? LevitTheme.pink : LevitTheme.muted)
        }
    }

    private func statusText(for score: ScoreEditorJudgeScore) -> String {
        if score.isCurrentlyScoring {
            return "Calificando"
        }
        if score.isComplete {
            return "Calificado"
        }
        if score.hasAnyScore {
            return "Incompleto"
        }
        return "Pendiente"
    }

    private func scoreText(_ value: Double) -> String {
        let rounded = value.rounded()
        if abs(value - rounded) < 0.001 {
            return "\(Int(rounded))"
        }
        return String(format: "%.1f", value)
    }
}

private struct ScoreEditorMetadataPill: View {
    let title: String
    let value: String
    let systemImage: String
    let options: [String]
    let isEnabled: Bool
    let onSelect: (String) -> Void

    @State private var isPresented = false

    var body: some View {
        Button {
            guard isEnabled, !options.isEmpty else { return }
            isPresented.toggle()
        } label: {
            HStack(spacing: 5) {
                Text(value.uppercased())
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
                Image(systemName: isPresented ? "chevron.up" : "chevron.down")
                    .font(.system(size: 8, weight: .black))
                    .foregroundStyle(LevitTheme.muted)
            }
            .font(.caption.weight(.black))
            .foregroundStyle(LevitTheme.muted)
            .padding(.horizontal, 9)
            .padding(.vertical, 6)
            .background(LevitTheme.solidSurface.opacity(0.72), in: Capsule())
            .overlay(Capsule().stroke(LevitTheme.line))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled || options.isEmpty)
        .opacity(isEnabled ? 1 : 0.58)
        .popover(isPresented: $isPresented, arrowEdge: .bottom) {
            dropdownContent
        }
    }

    private var dropdownContent: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 9) {
                Image(systemName: systemImage)
                    .font(.callout.weight(.black))
                    .foregroundStyle(LevitTheme.pink)
                    .frame(width: 22)
                Text(title)
                    .font(.caption.weight(.black))
                    .foregroundStyle(LevitTheme.muted)
                    .textCase(.uppercase)
            }
            .padding(.horizontal, 10)
            .padding(.top, 8)
            .padding(.bottom, 4)

            Divider()
                .overlay(LevitTheme.line)

            ForEach(options, id: \.normalizedKey) { option in
                Button {
                    isPresented = false
                    onSelect(option)
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: option.normalizedKey == value.normalizedKey ? "checkmark.circle.fill" : systemImage)
                            .font(.callout.weight(.black))
                            .foregroundStyle(option.normalizedKey == value.normalizedKey ? LevitTheme.pink : LevitTheme.muted)
                            .frame(width: 24)
                        Text(option.uppercased())
                            .font(.callout.weight(.black))
                            .foregroundStyle(LevitTheme.ink)
                            .lineLimit(1)
                            .minimumScaleFactor(0.72)
                        Spacer()
                    }
                    .padding(.horizontal, 11)
                    .padding(.vertical, 10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(option.normalizedKey == value.normalizedKey ? LevitTheme.palePink : Color.clear, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(8)
        .frame(width: 250, alignment: .topLeading)
        .background(LevitTheme.surface)
        #if os(iOS)
        .presentationCompactAdaptation(.popover)
        #endif
    }
}

struct JudgeActivityView: View {
    @EnvironmentObject private var store: JudgingStore
    @State private var isRefreshingActivity = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                header
                activityPanel
            }
            .padding(.horizontal, 34)
            .padding(.vertical, 28)
            .frame(maxWidth: 1240, alignment: .leading)
        }
        .background(LevitTheme.paper.ignoresSafeArea())
        .foregroundStyle(LevitTheme.ink)
        .task {
            await pollJudgeActivity()
        }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 22) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Actividad de jueces")
                    .font(.system(size: 38, weight: .black, design: .rounded))
                    .foregroundStyle(LevitTheme.ink)
                Text("Estado actual de cada juez en el programa")
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

    private var activityPanel: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                Label("Monitoreo en vivo", systemImage: "dot.radiowaves.left.and.right")
                    .font(.headline.weight(.black))
                    .foregroundStyle(LevitTheme.ink)

                Spacer()

                Text("Inactivo a los 10 min")
                    .font(.caption.weight(.black))
                    .foregroundStyle(LevitTheme.muted)

                RefreshDataButton(isRefreshing: isRefreshingActivity) {
                    Task { await refreshJudgeActivity() }
                }
                .disabled(!store.hasRemoteConfiguration)
                .opacity(store.hasRemoteConfiguration ? 1 : 0.58)
            }

            if store.latestJudgeActivities.isEmpty {
                Text(emptyMessage)
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(LevitTheme.muted)
                    .frame(maxWidth: .infinity, minHeight: 180, alignment: .center)
                    .background(LevitTheme.softFill, in: RoundedRectangle(cornerRadius: 15))
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 250), spacing: 10)], spacing: 10) {
                    ForEach(store.latestJudgeActivities) { activity in
                        JudgeActivityCard(activity: activity)
                    }
                }
            }
        }
        .padding(18)
        .background(LevitTheme.elevatedSurface, in: RoundedRectangle(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(LevitTheme.line))
    }

    private var emptyMessage: String {
        store.hasRemoteConfiguration
            ? "Todavía no hay actividad registrada en este programa."
            : "Supabase no está configurado."
    }

    @MainActor
    private func refreshJudgeActivity() async {
        guard !isRefreshingActivity else { return }
        isRefreshingActivity = true
        defer { isRefreshingActivity = false }
        await store.refreshJudgeActivity()
    }

    private func pollJudgeActivity() async {
        await refreshJudgeActivity()
        while !Task.isCancelled {
            try? await Task.sleep(nanoseconds: judgeActivityPollingIntervalNanoseconds)
            await refreshJudgeActivity()
        }
    }
}

private struct JudgeActivityCard: View {
    let activity: JudgeActivitySummary

    private var isInactive: Bool {
        activity.isInactive()
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: symbol)
                .font(.headline.weight(.black))
                .foregroundStyle(tint)
                .frame(width: 40, height: 40)
                .background(tint.opacity(0.14), in: RoundedRectangle(cornerRadius: 12, style: .continuous))

            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 8) {
                    Text(activity.judgeName)
                        .font(.headline.weight(.black))
                        .foregroundStyle(LevitTheme.ink)
                        .lineLimit(1)
                    Spacer(minLength: 6)
                    Text(relativeUpdatedAt)
                        .font(.caption2.monospacedDigit().weight(.black))
                        .foregroundStyle(isInactive ? .red : LevitTheme.muted)
                        .lineLimit(1)
                }

                Text(isInactive ? "Inactivo hace \(inactiveDuration)" : activity.statusTitle)
                    .font(.callout.weight(.black))
                    .foregroundStyle(isInactive ? .red : LevitTheme.ink)
                    .lineLimit(2)
                    .minimumScaleFactor(0.78)

                Text(isInactive ? activity.statusTitle : activity.detail)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(LevitTheme.muted)
                    .lineLimit(2)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, minHeight: 112, alignment: .topLeading)
        .background(LevitTheme.solidSurface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(isInactive ? Color.red.opacity(0.28) : LevitTheme.line))
    }

    private var symbol: String {
        if isInactive { return "clock.badge.exclamationmark" }
        switch activity.state {
        case .home:
            return "house.fill"
        case .viewingSheet:
            return "doc.text.magnifyingglass"
        case .leftSheet:
            return "rectangle.portrait.and.arrow.right"
        }
    }

    private var tint: Color {
        if isInactive { return .red }
        switch activity.state {
        case .home:
            return .green
        case .viewingSheet:
            return LevitTheme.pink
        case .leftSheet:
            return .orange
        }
    }

    private var relativeUpdatedAt: String {
        "hace \(durationText)"
    }

    private var inactiveDuration: String {
        durationText
    }

    private var durationText: String {
        let seconds = max(0, Int(Date().timeIntervalSince(activity.updatedAt)))
        if seconds < 60 {
            return "\(seconds)s"
        }
        let minutes = seconds / 60
        if minutes < 60 {
            return "\(minutes)m"
        }
        let hours = minutes / 60
        let remainingMinutes = minutes % 60
        return remainingMinutes == 0 ? "\(hours)h" : "\(hours)h \(remainingMinutes)m"
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

private struct AdminSpecialAwardButton: View {
    let category: SpecialAwardCategory
    let assignedRoutine: Routine?
    let isCurrentRoutine: Bool
    let isSaving: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(isCurrentRoutine ? LevitTheme.pinkGradient : LinearGradient(colors: [LevitTheme.palePink, LevitTheme.palePink], startPoint: .top, endPoint: .bottom))
                        if isSaving {
                            ProgressView()
                                .controlSize(.small)
                                .tint(isCurrentRoutine ? .white : LevitTheme.pink)
                        } else {
                            Image(systemName: isCurrentRoutine ? "checkmark" : category.systemImage)
                                .font(.caption.weight(.black))
                                .foregroundStyle(isCurrentRoutine ? .white : LevitTheme.pink)
                        }
                    }
                    .frame(width: 32, height: 32)

                    Text(category.title)
                        .font(.caption.weight(.black))
                        .foregroundStyle(LevitTheme.ink)
                        .lineLimit(2)
                        .minimumScaleFactor(0.72)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                Text(detailText)
                    .font(.caption2.weight(.black))
                    .foregroundStyle(isCurrentRoutine ? LevitTheme.pink : LevitTheme.muted)
                    .lineLimit(1)
                    .minimumScaleFactor(0.68)
            }
            .padding(10)
            .frame(maxWidth: .infinity, minHeight: 86, alignment: .leading)
            .background(isCurrentRoutine ? LevitTheme.palePink.opacity(0.74) : LevitTheme.solidSurface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(isCurrentRoutine ? LevitTheme.pink.opacity(0.38) : LevitTheme.line))
            .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private var detailText: String {
        if isCurrentRoutine {
            return "Asignada"
        }
        if let assignedRoutine {
            return "#\(assignedRoutine.id) \(assignedRoutine.name)"
        }
        return "Sin asignar"
    }
}

private struct AdminManualSpecialAwardField: View {
    let category: SpecialAwardCategory
    @Binding var value: String
    let currentValue: String?
    let isSaving: Bool
    let onSave: () -> Void
    let onClear: () -> Void

    private var hasSavedValue: Bool {
        !(currentValue?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
    }

    private var canSave: Bool {
        !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isSaving
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 8) {
                Image(systemName: category.systemImage)
                    .font(.caption.weight(.black))
                    .foregroundStyle(LevitTheme.pink)
                    .frame(width: 32, height: 32)
                    .background(LevitTheme.palePink, in: RoundedRectangle(cornerRadius: 10, style: .continuous))

                VStack(alignment: .leading, spacing: 2) {
                    Text(category.title)
                        .font(.caption.weight(.black))
                    Text(hasSavedValue ? "Guardada manualmente" : "Escritura manual")
                        .font(.caption2.weight(.black))
                        .foregroundStyle(hasSavedValue ? LevitTheme.pink : LevitTheme.muted)
                }

                Spacer()
            }

            HStack(spacing: 8) {
                TextField("Escribir nombre", text: $value)
                    .textInputAutocapitalization(.words)
                    .disableAutocorrection(true)
                    .font(.callout.weight(.black))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 11)
                    .background(LevitTheme.softFill, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(LevitTheme.line))

                Button(action: onSave) {
                    if isSaving {
                        ProgressView()
                            .controlSize(.small)
                            .tint(.white)
                    } else {
                        Image(systemName: "checkmark")
                            .font(.callout.weight(.black))
                    }
                }
                .frame(width: 44, height: 44)
                .foregroundStyle(.white)
                .background(LevitTheme.pinkGradient, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .disabled(!canSave)
                .opacity(canSave ? 1 : 0.48)
                .buttonStyle(.plain)

                Button(action: onClear) {
                    Image(systemName: "xmark")
                        .font(.callout.weight(.black))
                }
                .frame(width: 44, height: 44)
                .foregroundStyle(LevitTheme.muted)
                .background(LevitTheme.solidSurface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(LevitTheme.line))
                .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .disabled(isSaving || (!hasSavedValue && value.isEmpty))
                .opacity(isSaving || (!hasSavedValue && value.isEmpty) ? 0.48 : 1)
                .buttonStyle(.plain)
            }
        }
        .padding(10)
        .background(LevitTheme.solidSurface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(LevitTheme.line))
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
