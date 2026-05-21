import SwiftUI
import UniformTypeIdentifiers

struct PhoneContentView: View {
    @EnvironmentObject private var store: JudgingStore
    @State private var selectedTab: PhoneTab = .home
    @State private var addingJudge = false
    @State private var newJudgeName = ""
    @State private var isAdminJudgingPresented = false

    private var availableTabs: [PhoneTab] {
        store.isAdmin ? [.home, .admin, .dictamen, .favorites, .excel] : [.home, .routines, .judging]
    }

    var body: some View {
        ZStack {
            LevitTheme.paper.ignoresSafeArea()

            TabView(selection: $selectedTab) {
                ForEach(availableTabs) { tab in
                    tabContent(tab)
                        .tabItem {
                            Label(tab.title, systemImage: tab.symbol)
                        }
                        .tag(tab)
                }
            }
            .tint(LevitTheme.pink)

            if store.isLoadingBackendData {
                PhoneLoadingOverlay(message: store.backendLoadingMessage)
                    .transition(.opacity)
                    .zIndex(10)
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
        .task {
            await store.startRemoteSyncIfAvailable()
        }
        .fullScreenCover(isPresented: $isAdminJudgingPresented) {
            PhoneJudgingView(selectedTab: $selectedTab) {
                isAdminJudgingPresented = false
            }
            .environmentObject(store)
        }
        .onChange(of: store.isAdmin) { _, _ in
            if !availableTabs.contains(selectedTab) {
                selectedTab = .home
            }
        }
    }

    @ViewBuilder
    private func tabContent(_ tab: PhoneTab) -> some View {
        switch tab {
        case .home:
            PhoneHomeView(
                selectedTab: $selectedTab,
                addingJudge: $addingJudge,
                isAdminJudgingPresented: $isAdminJudgingPresented
            )
        case .routines:
            PhoneRoutinesView(
                selectedTab: $selectedTab,
                isAdminJudgingPresented: $isAdminJudgingPresented
            )
        case .judging:
            PhoneJudgingView(selectedTab: $selectedTab)
        case .favorites:
            PhoneFavoritesView()
        case .ranking:
            PhoneRankingView()
        case .dictamen:
            PhoneDictamenView()
        case .excel:
            PhoneExcelImportView()
        case .admin:
            PhoneAdminView(
                isAdminJudgingPresented: $isAdminJudgingPresented
            )
        }
    }
}

private enum PhoneTab: String, CaseIterable, Identifiable, Hashable {
    case home
    case routines
    case judging
    case favorites
    case ranking
    case dictamen
    case excel
    case admin

    var id: String { rawValue }

    var title: String {
        switch self {
        case .home: "Home"
        case .routines: "Rutinas"
        case .judging: "Jueceo"
        case .favorites: "Favoritos"
        case .ranking: "Ranking"
        case .dictamen: "Dictamen final"
        case .excel: "Subir Excel"
        case .admin: "Panel admin"
        }
    }

    var symbol: String {
        switch self {
        case .home: "house.fill"
        case .routines: "list.bullet"
        case .judging: "checklist"
        case .favorites: "star.fill"
        case .ranking: "chart.bar.fill"
        case .dictamen: "trophy.fill"
        case .excel: "square.and.arrow.up"
        case .admin: "gearshape.fill"
        }
    }
}

private struct PhoneHomeView: View {
    @EnvironmentObject private var store: JudgingStore
    @Binding var selectedTab: PhoneTab
    @Binding var addingJudge: Bool
    @Binding var isAdminJudgingPresented: Bool

    private var orderedRoutines: [Routine] {
        store.visibleRoutines.sorted(by: routineOrder)
    }

    private var pendingRoutines: [Routine] {
        let pending = orderedRoutines.filter { store.result(for: $0).total == 0 }
        return pending.isEmpty ? Array(orderedRoutines.prefix(4)) : Array(pending.prefix(4))
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    VStack(alignment: .leading, spacing: 18) {
                        topBar
                        hero
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 18)
                    .padding(.top, 14)
                    .padding(.bottom, 10)
                    .background(alignment: .trailing) {
                        DashboardHeroBackground(widthFraction: 2.0 / 3.0)
                    }

                    nextRoutines
                        .padding(.horizontal, 18)
                    primaryActions
                        .padding(.horizontal, 18)
                }
                .padding(.bottom, 28)
            }
            .background(DashboardBackground())
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private var topBar: some View {
        HStack(spacing: 12) {
            LevitBrand(isCompact: true)
            Spacer()
            PhoneJudgeMenu(addingJudge: $addingJudge)
        }
    }

    private var hero: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(store.selectedJudge)
                        .font(.system(size: 34, weight: .black, design: .rounded))
                        .foregroundStyle(LevitTheme.pink)
                        .lineLimit(1)
                        .minimumScaleFactor(0.62)
                    Text(store.selectedBlock?.name ?? "Bloque")
                        .font(.headline.weight(.bold))
                        .foregroundStyle(LevitTheme.muted)
                }

                Spacer()

                PhoneSyncBadge()
            }

            if store.isAdmin {
                adminSelectors
            }
        }
        .padding(18)
        .background(LevitTheme.elevatedSurface, in: RoundedRectangle(cornerRadius: 20))
        .overlay(RoundedRectangle(cornerRadius: 20).stroke(LevitTheme.line))
    }

    private var adminSelectors: some View {
        VStack(spacing: 10) {
            selectorRow {
                EventPill(isCompact: true)
            }

            selectorRow {
                BlockPill(isCompact: true)
            }
        }
    }

    private func selectorRow<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content()
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 14)
            .frame(minHeight: 50, alignment: .leading)
            .background(LevitTheme.solidSurface, in: RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(LevitTheme.line))
    }

    private var nextRoutines: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Próximas rutinas")
                    .font(.title3.weight(.black))
                Spacer()
                Button {
                    selectedTab = store.isAdmin ? .admin : .routines
                } label: {
                    Image(systemName: "arrow.right")
                        .font(.headline.weight(.bold))
                        .foregroundStyle(LevitTheme.pink)
                }
                .buttonStyle(.plain)
            }

            VStack(spacing: 10) {
                ForEach(pendingRoutines) { routine in
                    PhoneRoutineRow(routine: routine, total: store.result(for: routine).total) {
                        store.selectedRoutineID = routine.id
                        if store.isAdmin {
                            if store.isAdminEditingAsJudge {
                                isAdminJudgingPresented = true
                            } else {
                                selectedTab = .admin
                            }
                        } else {
                            selectedTab = .judging
                        }
                    }
                }
            }
        }
    }

    private var primaryActions: some View {
        HStack(spacing: 12) {
            Button {
                if store.isAdmin {
                    selectedTab = .admin
                    return
                }
                if let next = pendingRoutines.first ?? orderedRoutines.first {
                    store.selectedRoutineID = next.id
                }
                selectedTab = .judging
            } label: {
                Label(store.isAdmin ? "Panel admin" : "Calificar", systemImage: store.isAdmin ? "gearshape.fill" : "play.fill")
                    .font(.headline.weight(.black))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .foregroundStyle(.white)
                    .background(LevitTheme.pinkGradient, in: RoundedRectangle(cornerRadius: 17))
            }
            .buttonStyle(.plain)
            .disabled(!store.isAdmin && orderedRoutines.isEmpty)
            .opacity(!store.isAdmin && orderedRoutines.isEmpty ? 0.45 : 1)

            if !store.isAdmin {
                Button {
                    selectedTab = .routines
                } label: {
                    Image(systemName: "list.bullet")
                        .font(.headline.weight(.black))
                        .frame(width: 58, height: 52)
                        .foregroundStyle(LevitTheme.ink)
                        .background(LevitTheme.solidSurface, in: RoundedRectangle(cornerRadius: 17))
                        .overlay(RoundedRectangle(cornerRadius: 17).stroke(LevitTheme.line))
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func routineOrder(_ lhs: Routine, _ rhs: Routine) -> Bool {
        let lhsNumber = Int(lhs.id) ?? Int.max
        let rhsNumber = Int(rhs.id) ?? Int.max
        if lhsNumber == rhsNumber {
            return lhs.id.localizedStandardCompare(rhs.id) == .orderedAscending
        }
        return lhsNumber < rhsNumber
    }
}

private struct PhoneRoutinesView: View {
    @EnvironmentObject private var store: JudgingStore
    @Binding var selectedTab: PhoneTab
    @Binding var isAdminJudgingPresented: Bool
    @State private var searchText = ""
    @State private var filter: PhoneRoutineFilter = .all

    private var filteredRoutines: [Routine] {
        store.visibleRoutines
            .filter(matchesFilter)
            .filter(matchesSearch)
            .sorted(by: routineOrder)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 12) {
                searchField
                Picker("Filtro", selection: $filter) {
                    ForEach(PhoneRoutineFilter.allCases) { filter in
                        Text(filter.title).tag(filter)
                    }
                }
                .pickerStyle(.segmented)

                ScrollView {
                    LazyVStack(spacing: 10) {
                        ForEach(filteredRoutines) { routine in
                            PhoneRoutineRow(routine: routine, total: store.result(for: routine).total) {
                                store.selectedRoutineID = routine.id
                                if store.isAdmin {
                                    if store.isAdminEditingAsJudge {
                                        isAdminJudgingPresented = true
                                    } else {
                                        selectedTab = .admin
                                    }
                                } else {
                                    selectedTab = .judging
                                }
                            }
                        }
                    }
                    .padding(.bottom, 22)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .background(LevitTheme.paper)
            .navigationTitle("Rutinas")
            .toolbar {
                if store.isAdmin {
                    ToolbarItem(placement: .topBarTrailing) {
                        BlockPill(isCompact: true)
                    }
                }
            }
        }
    }

    private var searchField: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(LevitTheme.muted)
            TextField("Buscar", text: $searchText)
                .textInputAutocapitalization(.never)
                .disableAutocorrection(true)
        }
        .font(.callout.weight(.semibold))
        .padding(.horizontal, 14)
        .frame(height: 46)
        .background(LevitTheme.solidSurface, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(LevitTheme.line))
    }

    private func matchesFilter(_ routine: Routine) -> Bool {
        switch filter {
        case .all:
            true
        case .pending:
            store.result(for: routine).total == 0
        case .scored:
            store.result(for: routine).total > 0
        case .favorites:
            store.hasFavorite(routine)
        }
    }

    private func matchesSearch(_ routine: Routine) -> Bool {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return true }
        return [
            routine.id,
            routine.name,
            routine.academy,
            routine.genre,
            routine.division,
            routine.category
        ]
        .joined(separator: " ")
        .normalizedKey
        .contains(query.normalizedKey)
    }

    private func routineOrder(_ lhs: Routine, _ rhs: Routine) -> Bool {
        let lhsNumber = Int(lhs.id) ?? Int.max
        let rhsNumber = Int(rhs.id) ?? Int.max
        if lhsNumber == rhsNumber {
            return lhs.id.localizedStandardCompare(rhs.id) == .orderedAscending
        }
        return lhsNumber < rhsNumber
    }
}

private enum PhoneRoutineFilter: String, CaseIterable, Identifiable {
    case all
    case pending
    case scored
    case favorites

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: "Todas"
        case .pending: "Pend."
        case .scored: "Listas"
        case .favorites: "Fav."
        }
    }
}

private struct PhoneJudgingView: View {
    @EnvironmentObject private var store: JudgingStore
    @Binding var selectedTab: PhoneTab
    var onClose: (() -> Void)?

    var body: some View {
        NavigationStack {
            if let routine = store.selectedRoutine {
                PhoneScoreSheet(
                    routine: routine,
                    routines: sortedRoutines,
                    selectedTab: $selectedTab,
                    onClose: onClose
                )
            } else {
                ContentUnavailableView("Sin rutinas", systemImage: "tray")
                    .background(LevitTheme.paper)
            }
        }
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
}

private struct PhoneScoreSheet: View {
    @EnvironmentObject private var store: JudgingStore
    let routine: Routine
    let routines: [Routine]
    @Binding var selectedTab: PhoneTab
    var onClose: (() -> Void)?

    @State private var draftScores: [Int: String] = [:]
    @State private var penalty = "0"
    @State private var customPenalty = ""
    @State private var didSubmit = false
    @State private var errorMessage: String?
    @FocusState private var focusedCriterionID: Int?

    private var template: JudgingTemplate {
        store.template(for: routine)
    }

    private var scoringJudge: String {
        store.scoringJudge
    }

    private var subtotal: Double {
        max(0, scoreSubtotal + penaltyValue)
    }

    private var scoreSubtotal: Double {
        template.criteria.reduce(0) { $0 + scoreValue(for: $1) }
    }

    private var penaltyValue: Double {
        if penalty == "Otro" {
            return min(max(Double(customPenalty.replacingOccurrences(of: ",", with: ".")) ?? 0, -100), 0)
        }
        return Double(penalty) ?? 0
    }

    private var maxTotal: Double {
        template.maxScore > 0 ? template.maxScore : template.criteria.reduce(0) { $0 + $1.maxScore }
    }

    private var routineIndex: Int {
        (routines.firstIndex { $0.id == routine.id } ?? 0) + 1
    }

    private var nextRoutine: Routine? {
        guard let index = routines.firstIndex(where: { $0.id == routine.id }) else { return nil }
        let next = routines.index(after: index)
        return routines.indices.contains(next) ? routines[next] : nil
    }

    private var previousRoutine: Routine? {
        guard let index = routines.firstIndex(where: { $0.id == routine.id }), index > 0 else { return nil }
        return routines[routines.index(before: index)]
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                routineHeader
                totalPanel
                criteriaList
                penaltyControl
                favoriteButtons
                feedbackEditor
                saveButtons
            }
            .padding(.horizontal, 16)
            .padding(.top, 10)
            .padding(.bottom, 28)
        }
        .background(LevitTheme.paper)
        .navigationTitle("Jueceo")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if let onClose {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cerrar", action: onClose)
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    if let onClose {
                        onClose()
                    } else {
                        selectedTab = .routines
                    }
                } label: {
                    Image(systemName: "list.bullet")
                }
            }
        }
        .onAppear(perform: loadDraft)
        .onChange(of: routine.id) { _, _ in loadDraft() }
        .onChange(of: scoringJudge) { _, _ in loadDraft() }
    }

    private var routineHeader: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text("#\(routine.id)")
                    .font(.title2.monospacedDigit().weight(.black))
                    .foregroundStyle(LevitTheme.pink)
                Spacer()
                Text("\(routineIndex) / \(max(routines.count, 1))")
                    .font(.callout.monospacedDigit().weight(.bold))
                    .foregroundStyle(LevitTheme.muted)
            }

            Text(routine.name)
                .font(.system(size: 27, weight: .black, design: .rounded))
                .foregroundStyle(LevitTheme.ink)
                .lineLimit(2)
                .minimumScaleFactor(0.78)
            Text(routine.academy)
                .font(.headline.weight(.bold))
                .foregroundStyle(LevitTheme.muted)
                .lineLimit(2)

            HStack(spacing: 6) {
                LevitTag(routine.genre)
                LevitTag(routine.division)
                LevitTag(routine.category)
            }

            if store.isAdminEditingAsJudge {
                Label(scoringJudge, systemImage: "person.fill.viewfinder")
                    .font(.caption.weight(.black))
                    .foregroundStyle(LevitTheme.pink)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .background(LevitTheme.palePink, in: Capsule())
            }
        }
        .padding(16)
        .background(LevitTheme.elevatedSurface, in: RoundedRectangle(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(LevitTheme.line))
    }

    private var totalPanel: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Puntaje total")
                    .font(.caption.weight(.black))
                    .foregroundStyle(LevitTheme.muted)
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(subtotal.formatted(.number.precision(.fractionLength(0...1))))
                        .font(.system(size: 44, weight: .black, design: .rounded))
                        .foregroundStyle(LevitTheme.hotPink)
                    Text("/ \(maxTotal.formatted(.number.precision(.fractionLength(0...1))))")
                        .font(.headline.weight(.black))
                        .foregroundStyle(LevitTheme.muted)
                }
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 6) {
                Label(didSubmit ? "Guardado" : store.syncStatus.title, systemImage: didSubmit ? "checkmark.circle.fill" : store.syncStatus.systemImage)
                    .font(.caption.weight(.black))
                    .foregroundStyle(didSubmit ? Color.green : LevitTheme.muted)
                Text("Penalización \(penaltyValue.formatted(.number.precision(.fractionLength(0...1))))")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(LevitTheme.muted)
            }
        }
        .padding(16)
        .background(LevitTheme.solidSurface, in: RoundedRectangle(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(LevitTheme.line))
    }

    private var criteriaList: some View {
        VStack(alignment: .leading, spacing: 14) {
            ForEach(groupedCriteria, id: \.section) { group in
                VStack(alignment: .leading, spacing: 9) {
                    Text(group.section.uppercased())
                        .font(.caption.weight(.black))
                        .foregroundStyle(LevitTheme.muted)
                    VStack(spacing: 8) {
                        ForEach(group.criteria) { criterion in
                            PhoneCriterionRow(
                                criterion: criterion,
                                value: Binding(
                                    get: { draftScores[criterion.id] ?? "" },
                                    set: {
                                        draftScores[criterion.id] = sanitizedScoreText($0, maxScore: criterion.maxScore)
                                        didSubmit = false
                                        errorMessage = nil
                                    }
                                ),
                                onDecrement: { adjust(criterion, delta: -1) },
                                onIncrement: { adjust(criterion, delta: 1) },
                                focusedCriterionID: $focusedCriterionID
                            )
                        }
                    }
                }
            }

            if let errorMessage {
                Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                    .font(.callout.weight(.bold))
                    .foregroundStyle(.red)
                    .padding(.top, 2)
            }
        }
    }

    private var penaltyControl: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Penalización")
                .font(.caption.weight(.black))
                .foregroundStyle(LevitTheme.muted)

            HStack(spacing: 8) {
                ForEach(["0", "-1", "-2", "Otro"], id: \.self) { item in
                    Button {
                        penalty = item
                        if item != "Otro" {
                            customPenalty = ""
                        }
                        didSubmit = false
                    } label: {
                        Text(item)
                            .font(.callout.weight(.black))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .foregroundStyle(penalty == item ? LevitTheme.pink : LevitTheme.ink)
                            .background(penalty == item ? LevitTheme.palePink : LevitTheme.solidSurface, in: RoundedRectangle(cornerRadius: 12))
                            .overlay(RoundedRectangle(cornerRadius: 12).stroke(penalty == item ? LevitTheme.pink.opacity(0.46) : LevitTheme.line))
                    }
                    .buttonStyle(.plain)
                }
            }

            if penalty == "Otro" {
                TextField("-3", text: Binding(
                    get: { customPenalty },
                    set: {
                        customPenalty = sanitizedPenaltyText($0)
                        didSubmit = false
                    }
                ))
                .keyboardType(.numbersAndPunctuation)
                .textFieldStyle(.plain)
                .font(.title3.monospacedDigit().weight(.black))
                .padding(.horizontal, 14)
                .frame(height: 46)
                .background(LevitTheme.solidSurface, in: RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(LevitTheme.line))
            }
        }
    }

    private var favoriteButtons: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Favoritos")
                .font(.caption.weight(.black))
                .foregroundStyle(LevitTheme.muted)
            ForEach(FavoriteCategory.allCases) { category in
                let isSelected = store.isFavorite(routine, category: category, judge: scoringJudge)
                Button {
                    store.toggleFavorite(category, routine: routine, judge: scoringJudge)
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: category.systemImage)
                            .frame(width: 26)
                        Text(category.title)
                            .font(.callout.weight(.black))
                        Spacer()
                        Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    }
                    .padding(14)
                    .foregroundStyle(isSelected ? LevitTheme.pink : LevitTheme.ink)
                    .background(isSelected ? LevitTheme.palePink : LevitTheme.solidSurface, in: RoundedRectangle(cornerRadius: 14))
                    .overlay(RoundedRectangle(cornerRadius: 14).stroke(isSelected ? LevitTheme.pink.opacity(0.36) : LevitTheme.line))
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var feedbackEditor: some View {
        let key = store.feedbackKey(routineID: routine.id, judge: scoringJudge)
        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Retroalimentación")
                    .font(.caption.weight(.black))
                    .foregroundStyle(LevitTheme.muted)
                Spacer()
                Text("\((store.feedback[key] ?? "").count) / 300")
                    .font(.caption.monospacedDigit().weight(.bold))
                    .foregroundStyle(LevitTheme.muted)
            }

            TextEditor(text: Binding(
                get: { store.feedback[key] ?? "" },
                set: { store.setFeedback(String($0.prefix(300)), routine: routine, judge: scoringJudge) }
            ))
            .frame(minHeight: 118)
            .padding(8)
            .scrollContentBackground(.hidden)
            .background(LevitTheme.solidSurface, in: RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(LevitTheme.line))
        }
    }

    private var saveButtons: some View {
        VStack(spacing: 10) {
            Button {
                saveScores(advance: true)
            } label: {
                Label("Guardar y continuar", systemImage: "arrow.right")
                    .font(.headline.weight(.black))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .foregroundStyle(.white)
                    .background(LevitTheme.pinkGradient, in: RoundedRectangle(cornerRadius: 16))
            }
            .buttonStyle(.plain)

            HStack(spacing: 10) {
                Button {
                    if let previousRoutine {
                        saveScores(advance: false)
                        store.selectedRoutineID = previousRoutine.id
                    }
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.headline.weight(.black))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                }
                .buttonStyle(.plain)
                .foregroundStyle(previousRoutine == nil ? LevitTheme.muted.opacity(0.5) : LevitTheme.ink)
                .background(LevitTheme.solidSurface, in: RoundedRectangle(cornerRadius: 14))
                .overlay(RoundedRectangle(cornerRadius: 14).stroke(LevitTheme.line))
                .disabled(previousRoutine == nil)

                Button {
                    saveScores(advance: false)
                } label: {
                    Label("Guardar", systemImage: "checkmark")
                        .font(.headline.weight(.black))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                }
                .buttonStyle(.plain)
                .foregroundStyle(LevitTheme.ink)
                .background(LevitTheme.solidSurface, in: RoundedRectangle(cornerRadius: 14))
                .overlay(RoundedRectangle(cornerRadius: 14).stroke(LevitTheme.line))

                Button {
                    if let nextRoutine {
                        saveScores(advance: false)
                        store.selectedRoutineID = nextRoutine.id
                    }
                } label: {
                    Image(systemName: "chevron.right")
                        .font(.headline.weight(.black))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                }
                .buttonStyle(.plain)
                .foregroundStyle(nextRoutine == nil ? LevitTheme.muted.opacity(0.5) : LevitTheme.ink)
                .background(LevitTheme.solidSurface, in: RoundedRectangle(cornerRadius: 14))
                .overlay(RoundedRectangle(cornerRadius: 14).stroke(LevitTheme.line))
                .disabled(nextRoutine == nil)
            }
        }
    }

    private var groupedCriteria: [(section: String, criteria: [Criterion])] {
        Dictionary(grouping: template.criteria, by: \.section)
            .map { ($0.key, $0.value.sorted { $0.id < $1.id }) }
            .sorted { lhs, rhs in
                (lhs.criteria.first?.id ?? 0) < (rhs.criteria.first?.id ?? 0)
            }
    }

    private func loadDraft() {
        draftScores = Dictionary(uniqueKeysWithValues: template.criteria.map { criterion in
            let saved = store.score(for: routine, judge: scoringJudge, criterion: criterion)
            return (criterion.id, saved > 0 ? saved.formatted(.number.precision(.fractionLength(0...1))) : "")
        })
        loadPenalty(store.penalty(for: routine, judge: scoringJudge))
        didSubmit = false
        errorMessage = nil
        focusedCriterionID = nil
    }

    private func saveScores(advance: Bool) {
        guard validateScoresBeforeSaving() else { return }
        let values = template.criteria.map { criterion in
            let value = Double((draftScores[criterion.id] ?? "").replacingOccurrences(of: ",", with: ".")) ?? 0
            return (criterion: criterion, value: value)
        }
        store.submitScores(values, routine: routine, judge: scoringJudge, penalty: penaltyValue)
        didSubmit = true
        errorMessage = nil
        focusedCriterionID = nil
        if advance, let nextRoutine {
            store.selectedRoutineID = nextRoutine.id
        }
    }

    private func validateScoresBeforeSaving() -> Bool {
        guard let missingOrInvalid = template.criteria.first(where: { !isValidScoreText(draftScores[$0.id] ?? "", maxScore: $0.maxScore) }) else {
            return true
        }
        didSubmit = false
        errorMessage = "Completa todas las notas entre 0 y \(missingOrInvalid.maxScore.formatted(.number.precision(.fractionLength(0...1))))."
        focusedCriterionID = missingOrInvalid.id
        return false
    }

    private func isValidScoreText(_ text: String, maxScore: Double) -> Bool {
        let cleanText = text.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: ",", with: ".")
        guard !cleanText.isEmpty, let value = Double(cleanText) else { return false }
        return value >= 0 && value <= maxScore
    }

    private func scoreValue(for criterion: Criterion) -> Double {
        Double((draftScores[criterion.id] ?? "").replacingOccurrences(of: ",", with: ".")) ?? 0
    }

    private func loadPenalty(_ value: Double) {
        if abs(value) < 0.0001 {
            penalty = "0"
            customPenalty = ""
        } else if abs(value + 1) < 0.0001 {
            penalty = "-1"
            customPenalty = ""
        } else if abs(value + 2) < 0.0001 {
            penalty = "-2"
            customPenalty = ""
        } else {
            penalty = "Otro"
            customPenalty = value.formatted(.number.precision(.fractionLength(0...1)))
        }
    }

    private func sanitizedPenaltyText(_ text: String) -> String {
        let normalized = text.replacingOccurrences(of: ",", with: ".")
        let trimmed = normalized.trimmingCharacters(in: .whitespacesAndNewlines)
        let isNegative = trimmed.hasPrefix("-")
        let allowed = trimmed.filter { "0123456789.".contains($0) }
        let parts = allowed.split(separator: ".", omittingEmptySubsequences: false)
        let compact = parts.count > 1 ? "\(parts[0]).\(parts.dropFirst().joined())" : allowed
        if compact.isEmpty {
            return isNegative ? "-" : ""
        }
        let signed = isNegative ? "-\(compact)" : compact
        guard var value = Double(signed) else { return signed }
        if !isNegative {
            value = -abs(value)
        }
        return min(max(value, -100), 0).formatted(.number.precision(.fractionLength(0...1)))
    }

    private func sanitizedScoreText(_ text: String, maxScore: Double) -> String {
        let normalized = text.replacingOccurrences(of: ",", with: ".")
        let allowed = normalized.filter { "0123456789.".contains($0) }
        let parts = allowed.split(separator: ".", omittingEmptySubsequences: false)
        let compact = parts.count > 1 ? "\(parts[0]).\(parts.dropFirst().joined())" : allowed
        if compact == "." {
            return ""
        }
        guard let value = Double(compact) else { return compact }
        return min(max(value, 0), maxScore).formatted(.number.precision(.fractionLength(0...1)))
    }

    private func adjust(_ criterion: Criterion, delta: Double) {
        let current = scoreValue(for: criterion)
        let next = min(max(current + delta, 0), criterion.maxScore)
        draftScores[criterion.id] = next.formatted(.number.precision(.fractionLength(0...1)))
        didSubmit = false
        errorMessage = nil
    }
}

private struct PhoneFavoritesView: View {
    @EnvironmentObject private var store: JudgingStore

    private var favorites: [FavoriteSelectionSummary] {
        store.favoriteSummaries
    }

    private var rankingBlocks: [FavoriteRankingBlock] {
        store.favoriteRankingBlocks
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    HStack(spacing: 12) {
                        PhoneMetricCard(icon: "star.fill", value: "\(favorites.count)", label: "Total")
                        PhoneMetricCard(icon: "icloud.fill", value: store.pendingSyncCount == 0 ? "OK" : "\(store.pendingSyncCount)", label: "Sync")
                    }

                    if rankingBlocks.isEmpty {
                        PhoneEmptyState(
                            icon: "star.slash",
                            title: "Sin favoritos",
                            detail: "El top 3 de cada bloque aparece acá."
                        )
                    } else {
                        ForEach(rankingBlocks) { block in
                            PhoneFavoriteRankingBlock(block: block)
                        }
                    }
                }
                .padding(16)
                .padding(.bottom, 24)
            }
            .background(LevitTheme.paper)
            .navigationTitle("Favoritos")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    BlockPill(isCompact: true)
                }
            }
        }
    }
}

private struct PhoneFavoriteRankingBlock: View {
    let block: FavoriteRankingBlock

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label(block.blockName, systemImage: "square.stack.3d.up.fill")
                    .font(.headline.weight(.black))
                    .foregroundStyle(LevitTheme.pink)
                Spacer()
                Text("\(block.totalVotes) voto\(block.totalVotes == 1 ? "" : "s")")
                    .font(.caption.monospacedDigit().weight(.black))
                    .foregroundStyle(LevitTheme.muted)
            }

            VStack(spacing: 10) {
                ForEach(block.categories) { ranking in
                    PhoneFavoriteCategoryRanking(ranking: ranking)
                }
            }
        }
        .padding(16)
        .background(LevitTheme.elevatedSurface, in: RoundedRectangle(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(LevitTheme.line))
    }
}

private struct PhoneFavoriteCategoryRanking: View {
    let ranking: FavoriteCategoryRanking

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(ranking.category.title, systemImage: ranking.category.systemImage)
                .font(.headline.weight(.black))
                .foregroundStyle(LevitTheme.pink)

            if ranking.items.isEmpty {
                Text("Sin votos")
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(LevitTheme.muted)
                    .frame(maxWidth: .infinity, minHeight: 52, alignment: .center)
                    .background(LevitTheme.softFill, in: RoundedRectangle(cornerRadius: 14))
            } else {
                VStack(spacing: 8) {
                    ForEach(ranking.items) { item in
                        PhoneFavoriteRankingRow(item: item)
                    }
                }
            }
        }
        .padding(14)
        .background(LevitTheme.solidSurface, in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(LevitTheme.line))
    }
}

private struct PhoneFavoriteRankingRow: View {
    let item: FavoriteRankingItem

    var body: some View {
        HStack(spacing: 12) {
            Text("\(item.rank)")
                .font(.headline.weight(.black))
                .foregroundStyle(item.rank == 1 ? .white : LevitTheme.pink)
                .frame(width: 36, height: 36)
                .background(item.rank == 1 ? LevitTheme.pink : LevitTheme.palePink, in: Circle())

            VStack(alignment: .leading, spacing: 3) {
                Text(item.routine.academy.isEmpty ? item.routine.name : item.routine.academy)
                    .font(.callout.weight(.black))
                    .lineLimit(1)
                Text("#\(item.routine.id) \(item.routine.name)")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(LevitTheme.muted)
                    .lineLimit(1)
            }

            Spacer()

            Text("\(item.votes)")
                .font(.headline.monospacedDigit().weight(.black))
        }
        .padding(12)
        .foregroundStyle(LevitTheme.ink)
        .background(item.rank == 1 ? LevitTheme.palePink.opacity(0.72) : LevitTheme.softFill, in: RoundedRectangle(cornerRadius: 14))
    }
}

private struct PhoneDictamenView: View {
    @EnvironmentObject private var store: JudgingStore
    @State private var selectedGroupID: String?
    @State private var sharing = false

    private var groups: [PhoneDictamenGroup] {
        Dictionary(grouping: store.rankings) { result in
            PhoneDictamenGroup.id(
                genre: emptyFallback(result.routine.genre),
                division: emptyFallback(result.routine.division),
                category: emptyFallback(result.routine.category)
            )
        }
        .compactMap { _, items -> PhoneDictamenGroup? in
            guard let sample = items.first?.routine else { return nil }
            return PhoneDictamenGroup(
                genre: emptyFallback(sample.genre),
                division: emptyFallback(sample.division),
                category: emptyFallback(sample.category),
                results: sortedResults(items)
            )
        }
        .sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
    }

    private var selectedGroup: PhoneDictamenGroup? {
        if let selectedGroupID,
           let group = groups.first(where: { $0.id == selectedGroupID }) {
            return group
        }
        return groups.first
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if let selectedGroup {
                        selectedSummary(selectedGroup)
                        podium(selectedGroup)
                        exportButton(selectedGroup)
                    } else {
                        PhoneEmptyState(
                            icon: "trophy",
                            title: "Sin dictamen",
                            detail: "Cuando haya calificaciones, las categorías aparecerán acá."
                        )
                    }

                    groupsList
                }
                .padding(16)
                .padding(.bottom, 24)
            }
            .background(LevitTheme.paper)
            .navigationTitle("Dictamen final")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    BlockPill(isCompact: true)
                }
            }
            .sheet(isPresented: $sharing) {
                if let url = store.lastPDFURL {
                    ShareSheet(items: [url])
                }
            }
        }
    }

    private func selectedSummary(_ group: PhoneDictamenGroup) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "trophy.fill")
                .font(.headline.weight(.bold))
                .foregroundStyle(LevitTheme.pink)
                .frame(width: 38, height: 38)
                .background(LevitTheme.palePink, in: Circle())
            VStack(alignment: .leading, spacing: 3) {
                Text(group.title)
                    .font(.headline.weight(.black))
                    .lineLimit(2)
                Text("\(group.completedCount) / \(group.results.count) calificadas")
                    .font(.caption.monospacedDigit().weight(.bold))
                    .foregroundStyle(LevitTheme.muted)
            }
        }
        .padding(16)
        .foregroundStyle(LevitTheme.ink)
        .background(LevitTheme.elevatedSurface, in: RoundedRectangle(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(LevitTheme.line))
    }

    private func podium(_ group: PhoneDictamenGroup) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Podio")
                .font(.caption.weight(.black))
                .foregroundStyle(LevitTheme.muted)

            VStack(spacing: 10) {
                ForEach(Array(group.podium.enumerated()), id: \.element.id) { index, result in
                    PhoneRankingRow(position: index + 1, result: result)
                }
            }
        }
    }

    private func exportButton(_ group: PhoneDictamenGroup) -> some View {
        Button {
            store.exportPDF(results: group.results, title: "Dictamen final - \(group.title)")
            sharing = store.lastPDFURL != nil
        } label: {
            Label("Exportar dictamen", systemImage: "doc.richtext")
                .font(.headline.weight(.black))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 15)
                .foregroundStyle(.white)
                .background(LevitTheme.pinkGradient, in: RoundedRectangle(cornerRadius: 16))
        }
        .buttonStyle(.plain)
    }

    private var groupsList: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Categorías")
                .font(.caption.weight(.black))
                .foregroundStyle(LevitTheme.muted)

            VStack(spacing: 10) {
                ForEach(groups) { group in
                    Button {
                        selectedGroupID = group.id
                    } label: {
                        PhoneDictamenGroupRow(group: group, isSelected: group.id == selectedGroup?.id)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func sortedResults(_ items: [RoutineResult]) -> [RoutineResult] {
        items.sorted {
            if $0.aggregateTotal == $1.aggregateTotal {
                return (Int($0.routine.id) ?? 0) < (Int($1.routine.id) ?? 0)
            }
            return $0.aggregateTotal > $1.aggregateTotal
        }
    }

    private func emptyFallback(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "SIN DATO" : value
    }
}

private struct PhoneDictamenGroup: Identifiable {
    let genre: String
    let division: String
    let category: String
    let results: [RoutineResult]

    var id: String { Self.id(genre: genre, division: division, category: category) }
    var title: String { "\(genre) · \(division) · \(category)" }
    var completedCount: Int { results.filter { $0.aggregateTotal > 0 }.count }
    var podium: [RoutineResult] { Array(results.filter { $0.aggregateTotal > 0 }.prefix(3)) }

    static func id(genre: String, division: String, category: String) -> String {
        [genre, division, category].map(\.normalizedKey).joined(separator: "|")
    }
}

private struct PhoneDictamenGroupRow: View {
    let group: PhoneDictamenGroup
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: isSelected ? "trophy.fill" : "circle")
                .font(.headline.weight(.bold))
                .foregroundStyle(isSelected ? LevitTheme.pink : LevitTheme.muted)
                .frame(width: 32, height: 32)

            VStack(alignment: .leading, spacing: 4) {
                Text(group.genre)
                    .font(.callout.weight(.black))
                    .lineLimit(1)
                HStack(spacing: 6) {
                    LevitTag(group.division)
                    LevitTag(group.category)
                }
            }

            Spacer()

            Text("\(group.completedCount)/\(group.results.count)")
                .font(.caption.monospacedDigit().weight(.black))
                .foregroundStyle(LevitTheme.muted)
        }
        .padding(14)
        .foregroundStyle(LevitTheme.ink)
        .background(isSelected ? LevitTheme.palePink : LevitTheme.solidSurface, in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(isSelected ? LevitTheme.pink.opacity(0.34) : LevitTheme.line))
    }
}

private struct PhoneExcelImportView: View {
    @EnvironmentObject private var store: JudgingStore
    @State private var eventName = ""
    @State private var eventSlug = ""
    @State private var selectedFileURL: URL?
    @State private var isPickingFile = false
    @State private var isUploading = false
    @State private var lastUpload: ExcelImportSummary?
    @State private var errorMessage: String?

    private var canUpload: Bool {
        store.hasRemoteConfiguration
            && selectedFileURL != nil
            && !eventName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !eventSlug.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !isUploading
    }

    private var excelTypes: [UTType] {
        [UTType(filenameExtension: "xlsx"), UTType(filenameExtension: "xls")].compactMap { $0 }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    eventFields
                    filePicker
                    uploadButton
                    statusPanel
                }
                .padding(16)
                .padding(.bottom, 24)
            }
            .background(LevitTheme.paper)
            .navigationTitle("Excel")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    PhoneSyncBadge()
                }
            }
            .fileImporter(
                isPresented: $isPickingFile,
                allowedContentTypes: excelTypes,
                allowsMultipleSelection: false,
                onCompletion: handleFileSelection
            )
        }
    }

    private var eventFields: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Evento")
                .font(.caption.weight(.black))
                .foregroundStyle(LevitTheme.muted)

            TextField("Nombre del evento", text: $eventName)
                .textInputAutocapitalization(.words)
                .onChange(of: eventName) { oldValue, newValue in
                    if eventSlug.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || eventSlug == slug(for: oldValue) {
                        eventSlug = slug(for: newValue)
                    }
                }
                .modifier(PhoneImportFieldStyle())

            TextField("Slug", text: $eventSlug)
                .textInputAutocapitalization(.never)
                .disableAutocorrection(true)
                .onChange(of: eventSlug) { _, newValue in
                    let clean = slug(for: newValue)
                    if clean != newValue {
                        eventSlug = clean
                    }
                }
                .modifier(PhoneImportFieldStyle())
        }
    }

    private var filePicker: some View {
        Button {
            isPickingFile = true
        } label: {
            HStack(spacing: 13) {
                Image(systemName: "doc.badge.plus")
                    .font(.headline.weight(.bold))
                    .foregroundStyle(LevitTheme.pink)
                    .frame(width: 38, height: 38)
                    .background(LevitTheme.palePink, in: Circle())
                VStack(alignment: .leading, spacing: 3) {
                    Text(selectedFileURL?.lastPathComponent ?? "Seleccionar Excel")
                        .font(.headline.weight(.black))
                        .lineLimit(1)
                    Text(selectedFileURL.map(fileSizeText) ?? ".xlsx o .xls")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(LevitTheme.muted)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.black))
                    .foregroundStyle(LevitTheme.muted)
            }
            .padding(16)
            .foregroundStyle(LevitTheme.ink)
            .background(LevitTheme.solidSurface, in: RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(LevitTheme.line))
        }
        .buttonStyle(.plain)
    }

    private var uploadButton: some View {
        Button {
            Task { await uploadSelectedFile() }
        } label: {
            HStack(spacing: 10) {
                if isUploading {
                    ProgressView()
                        .tint(.white)
                } else {
                    Image(systemName: "icloud.and.arrow.up.fill")
                }
                Text(isUploading ? "Subiendo" : "Subir Excel")
            }
            .font(.headline.weight(.black))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .foregroundStyle(.white)
            .background(LevitTheme.pinkGradient, in: RoundedRectangle(cornerRadius: 16))
        }
        .buttonStyle(.plain)
        .disabled(!canUpload)
        .opacity(canUpload ? 1 : 0.45)
    }

    private var statusPanel: some View {
        VStack(spacing: 10) {
            PhoneImportStatusRow(
                icon: store.hasRemoteConfiguration ? "checkmark.icloud.fill" : "icloud.slash",
                title: store.hasRemoteConfiguration ? "Supabase conectado" : "Modo local",
                detail: store.syncMessage ?? store.syncStatus.title,
                tint: store.hasRemoteConfiguration ? .green : LevitTheme.muted
            )

            if let lastUpload {
                PhoneImportStatusRow(
                    icon: "checkmark.circle.fill",
                    title: lastUpload.eventName,
                    detail: "\(lastUpload.fileName) enviado",
                    tint: .green
                )
            }

            if let errorMessage {
                PhoneImportStatusRow(
                    icon: "exclamationmark.triangle.fill",
                    title: "No se pudo subir",
                    detail: errorMessage,
                    tint: .red
                )
            }
        }
    }

    private func handleFileSelection(_ result: Result<[URL], Error>) {
        errorMessage = nil
        switch result {
        case let .success(urls):
            guard let url = urls.first else { return }
            selectedFileURL = url
            let name = url.deletingPathExtension().lastPathComponent
            if eventName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                eventName = name
            }
            if eventSlug.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                eventSlug = slug(for: name)
            }
        case let .failure(error):
            errorMessage = error.localizedDescription
        }
    }

    private func uploadSelectedFile() async {
        guard let selectedFileURL else { return }
        isUploading = true
        errorMessage = nil
        defer { isUploading = false }

        do {
            lastUpload = try await store.uploadExcelImport(
                fileURL: selectedFileURL,
                eventName: eventName,
                eventSlug: eventSlug
            )
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func slug(for value: String) -> String {
        value.stableRemoteID
    }

    private func fileSizeText(for url: URL) -> String {
        guard
            let values = try? url.resourceValues(forKeys: [.fileSizeKey]),
            let size = values.fileSize
        else {
            return "Excel seleccionado"
        }
        return ByteCountFormatter.string(fromByteCount: Int64(size), countStyle: .file)
    }
}

private struct PhoneImportStatusRow: View {
    let icon: String
    let title: String
    let detail: String
    let tint: Color

    var body: some View {
        HStack(spacing: 13) {
            Image(systemName: icon)
                .font(.headline.weight(.black))
                .foregroundStyle(tint)
                .frame(width: 38, height: 38)
                .background(tint.opacity(0.12), in: Circle())

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.callout.weight(.black))
                    .lineLimit(1)
                Text(detail)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(LevitTheme.muted)
                    .lineLimit(2)
            }

            Spacer()
        }
        .padding(14)
        .foregroundStyle(LevitTheme.ink)
        .background(LevitTheme.solidSurface, in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(LevitTheme.line))
    }
}

private struct PhoneImportFieldStyle: ViewModifier {
    func body(content: Content) -> some View {
        content
            .font(.headline.weight(.bold))
            .padding(.horizontal, 14)
            .frame(height: 50)
            .foregroundStyle(LevitTheme.ink)
            .background(LevitTheme.solidSurface, in: RoundedRectangle(cornerRadius: 15))
            .overlay(RoundedRectangle(cornerRadius: 15).stroke(LevitTheme.line))
    }
}

private struct PhoneRankingView: View {
    @EnvironmentObject private var store: JudgingStore
    @State private var sharing = false

    private var completedResults: [RoutineResult] {
        store.rankings.filter { $0.total > 0 }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(spacing: 10) {
                    ForEach(Array(completedResults.enumerated()), id: \.element.id) { index, result in
                        PhoneRankingRow(position: index + 1, result: result)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, 22)
            }
            .background(LevitTheme.paper)
            .navigationTitle("Ranking")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        store.exportPDF(results: store.rankings, title: "Calificaciones y dictamen final")
                        sharing = store.lastPDFURL != nil
                    } label: {
                        Image(systemName: "doc.richtext")
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    BlockPill(isCompact: true)
                }
            }
            .sheet(isPresented: $sharing) {
                if let url = store.lastPDFURL {
                    ShareSheet(items: [url])
                }
            }
        }
    }
}

private struct PhoneAdminView: View {
    @EnvironmentObject private var store: JudgingStore
    @Binding var isAdminJudgingPresented: Bool

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    driveExport
                    editAsJudge
                }
                .padding(16)
                .padding(.bottom, 24)
            }
            .background(LevitTheme.paper)
            .navigationTitle("Panel admin")
        }
    }

    private var editAsJudge: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Editar como juez")
                .font(.caption.weight(.black))
                .foregroundStyle(LevitTheme.muted)

            Menu {
                ForEach(store.orderedEditableJudges, id: \.self) { judge in
                    Button {
                        if let routine = store.selectedRoutine ?? store.visibleRoutines.first {
                            store.beginAdminScoring(judge: judge, routine: routine)
                            isAdminJudgingPresented = true
                        }
                    } label: {
                        Label(judge, systemImage: judge == store.scoringJudge ? "checkmark.circle.fill" : "person")
                    }
                }
                if store.isAdminEditingAsJudge {
                    Divider()
                    Button {
                        store.clearAdminScoringOverride()
                    } label: {
                        Label("Salir de edición", systemImage: "xmark.circle")
                    }
                }
            } label: {
                PhoneActionRow(
                    title: store.isAdminEditingAsJudge ? store.scoringJudge : "Elegir juez",
                    detail: "",
                    icon: "person.fill.viewfinder",
                    color: LevitTheme.pink
                )
            }
        }
    }

    private var driveExport: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Drive")
                .font(.caption.weight(.black))
                .foregroundStyle(LevitTheme.muted)

            Button {
                guard !store.driveExportStatus.isExporting else { return }
                Task { await store.exportSelectedBlockToDrive() }
            } label: {
                HStack(spacing: 13) {
                    if store.driveExportStatus.isExporting {
                        ProgressView()
                            .tint(LevitTheme.pink)
                            .frame(width: 32, height: 32)
                    } else {
                        Image(systemName: store.driveExportStatus.systemImage)
                            .font(.headline.weight(.bold))
                            .frame(width: 32, height: 32)
                            .foregroundStyle(driveColor)
                    }
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Exportar a Drive")
                            .font(.headline.weight(.black))
                        Text(store.driveExportMessage ?? driveHelpText)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(LevitTheme.muted)
                            .lineLimit(2)
                    }
                    Spacer()
                }
                .padding(16)
                .foregroundStyle(LevitTheme.ink)
                .background(LevitTheme.solidSurface, in: RoundedRectangle(cornerRadius: 16))
                .overlay(RoundedRectangle(cornerRadius: 16).stroke(LevitTheme.line))
            }
            .buttonStyle(.plain)
        }
    }

    private var driveHelpText: String {
        store.hasGoogleDriveConfiguration
            ? "Bloque, academia, coreografía y juez"
            : "Faltan credenciales Google"
    }

    private var driveColor: Color {
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

private struct PhoneJudgeMenu: View {
    @EnvironmentObject private var store: JudgingStore
    @Binding var addingJudge: Bool
    @State private var judgePendingDeletion: String?

    var body: some View {
        Menu {
            ForEach(store.orderedJudges, id: \.self) { judge in
                Button {
                    store.selectJudge(judge)
                } label: {
                    Label(judge, systemImage: judge == store.selectedJudge ? "checkmark.circle.fill" : "person")
                }
            }
            Divider()
            if !store.deletableJudges.isEmpty {
                Menu {
                    ForEach(store.deletableJudges, id: \.self) { judge in
                        Button(role: .destructive) {
                            judgePendingDeletion = judge
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
            HStack(spacing: 8) {
                Text(String(store.selectedJudge.prefix(2)))
                    .font(.caption.weight(.black))
                    .frame(width: 34, height: 34)
                    .foregroundStyle(LevitTheme.pink)
                    .background(LevitTheme.palePink, in: Circle())
                Image(systemName: "chevron.down")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(LevitTheme.muted)
            }
        }
        .alert("Borrar juez", isPresented: Binding(
            get: { judgePendingDeletion != nil },
            set: { if !$0 { judgePendingDeletion = nil } }
        )) {
            Button("Borrar", role: .destructive) {
                if let judgePendingDeletion {
                    store.deleteJudge(judgePendingDeletion)
                }
                judgePendingDeletion = nil
            }
            Button("Cancelar", role: .cancel) {
                judgePendingDeletion = nil
            }
        } message: {
            Text("Se van a borrar sus puntajes, devoluciones, penalizaciones y favoritos locales.")
        }
    }
}

private struct PhoneSyncBadge: View {
    @EnvironmentObject private var store: JudgingStore

    var body: some View {
        Label(store.syncStatus.title, systemImage: store.syncStatus.systemImage)
            .font(.caption.weight(.black))
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .foregroundStyle(color)
            .background(color.opacity(0.12), in: Capsule())
    }

    private var color: Color {
        switch store.syncStatus {
        case .online, .localOnly:
            .green
        case .connecting, .syncing:
            .blue
        case .pending:
            .orange
        case .offline:
            .red
        }
    }
}

private struct PhoneEmptyState: View {
    let icon: String
    let title: String
    let detail: String

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.title3.weight(.bold))
                .foregroundStyle(LevitTheme.muted)
                .frame(width: 44, height: 44)
                .background(LevitTheme.softFill, in: Circle())

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline.weight(.black))
                Text(detail)
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(LevitTheme.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(16)
        .foregroundStyle(LevitTheme.ink)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(LevitTheme.solidSurface, in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(LevitTheme.line))
    }
}

private struct PhoneMetricCard: View {
    let icon: String
    let value: String
    let label: String

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            Image(systemName: icon)
                .font(.headline.weight(.bold))
                .foregroundStyle(LevitTheme.pink)
            Text(value)
                .font(.title2.weight(.black))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(label)
                .font(.caption.weight(.bold))
                .foregroundStyle(LevitTheme.muted)
        }
        .padding(14)
        .frame(maxWidth: .infinity, minHeight: 104, alignment: .leading)
        .background(LevitTheme.solidSurface, in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(LevitTheme.line))
    }
}

private struct PhoneChip: View {
    let icon: String
    let text: String

    var body: some View {
        Label(text, systemImage: icon)
            .font(.caption.weight(.black))
            .lineLimit(1)
            .minimumScaleFactor(0.72)
            .foregroundStyle(LevitTheme.pink)
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(LevitTheme.palePink, in: Capsule())
    }
}

private struct PhoneRoutineRow: View {
    let routine: Routine
    let total: Double
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Text("#\(routine.id)")
                    .font(.headline.monospacedDigit().weight(.black))
                    .foregroundStyle(LevitTheme.pink)
                    .frame(width: 58, alignment: .leading)

                VStack(alignment: .leading, spacing: 4) {
                    Text(routine.name)
                        .font(.callout.weight(.black))
                        .foregroundStyle(LevitTheme.ink)
                        .lineLimit(1)
                    Text(routine.academy)
                        .font(.caption.weight(.bold))
                        .foregroundStyle(LevitTheme.muted)
                        .lineLimit(1)
                    HStack(spacing: 5) {
                        LevitTag(routine.genre)
                        LevitTag(routine.category)
                    }
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 3) {
                    Text(total > 0 ? total.formatted(.number.precision(.fractionLength(1))) : "-")
                        .font(.headline.monospacedDigit().weight(.black))
                        .foregroundStyle(total > 0 ? LevitTheme.ink : LevitTheme.muted)
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.black))
                        .foregroundStyle(LevitTheme.muted)
                }
            }
            .padding(14)
            .background(LevitTheme.solidSurface, in: RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(LevitTheme.line))
        }
        .buttonStyle(.plain)
    }
}

private struct PhoneCriterionRow: View {
    let criterion: Criterion
    @Binding var value: String
    let onDecrement: () -> Void
    let onIncrement: () -> Void
    var focusedCriterionID: FocusState<Int?>.Binding

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 10) {
                Text("\(criterion.id).")
                    .font(.headline.monospacedDigit().weight(.black))
                    .foregroundStyle(LevitTheme.pink)
                    .frame(width: 34, alignment: .leading)
                VStack(alignment: .leading, spacing: 3) {
                    Text(criterion.label)
                        .font(.callout.weight(.black))
                        .foregroundStyle(LevitTheme.ink)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("0 a \(criterion.maxScore.formatted(.number.precision(.fractionLength(0...1))))")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(LevitTheme.muted)
                }
            }

            HStack(spacing: 12) {
                Button(action: onDecrement) {
                    Image(systemName: "minus")
                        .font(.headline.weight(.black))
                        .frame(width: 44, height: 44)
                        .foregroundStyle(LevitTheme.ink)
                        .background(LevitTheme.softFill, in: Circle())
                }
                .buttonStyle(.plain)

                TextField("0", text: $value)
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.center)
                    .font(.system(size: 30, weight: .black, design: .rounded).monospacedDigit())
                    .foregroundStyle(LevitTheme.ink)
                    .frame(maxWidth: .infinity)
                    .frame(height: 48)
                    .background(LevitTheme.softFill, in: RoundedRectangle(cornerRadius: 14))
                    .focused(focusedCriterionID, equals: criterion.id)

                Button(action: onIncrement) {
                    Image(systemName: "plus")
                        .font(.headline.weight(.black))
                        .frame(width: 44, height: 44)
                        .foregroundStyle(LevitTheme.ink)
                        .background(LevitTheme.softFill, in: Circle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(14)
        .background(LevitTheme.solidSurface, in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(LevitTheme.line))
    }
}

private struct PhoneRankingRow: View {
    let position: Int
    let result: RoutineResult

    var body: some View {
        HStack(spacing: 12) {
            Text("\(position)")
                .font(.headline.weight(.black))
                .foregroundStyle(position <= 3 ? .white : LevitTheme.pink)
                .frame(width: 38, height: 38)
                .background(position <= 3 ? LevitTheme.pink : LevitTheme.palePink, in: Circle())

            VStack(alignment: .leading, spacing: 4) {
                Text(result.routine.academy.isEmpty ? result.routine.name : result.routine.academy)
                    .font(.callout.weight(.black))
                    .lineLimit(1)
                Text("#\(result.routine.id) \(result.routine.name)")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(LevitTheme.muted)
                    .lineLimit(1)
            }

            Spacer()

            Text(result.aggregateTotal.formatted(.number.precision(.fractionLength(1))))
                .font(.headline.monospacedDigit().weight(.black))
        }
        .padding(14)
        .background(position == 1 ? LevitTheme.palePink : LevitTheme.solidSurface, in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(LevitTheme.line))
    }
}

private struct PhoneActionRow: View {
    let title: String
    let detail: String
    let icon: String
    let color: Color

    var body: some View {
        HStack(spacing: 13) {
            Image(systemName: icon)
                .font(.headline.weight(.bold))
                .frame(width: 36, height: 36)
                .foregroundStyle(color)
                .background(color.opacity(0.12), in: Circle())
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.headline.weight(.black))
                if !detail.isEmpty {
                    Text(detail)
                        .font(.caption.weight(.bold))
                        .foregroundStyle(LevitTheme.muted)
                }
            }
            Spacer()
            Image(systemName: "chevron.down")
                .font(.caption.weight(.black))
                .foregroundStyle(LevitTheme.muted)
        }
        .padding(16)
        .foregroundStyle(LevitTheme.ink)
        .background(LevitTheme.solidSurface, in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(LevitTheme.line))
    }
}

private struct PhoneLoadingOverlay: View {
    let message: String

    var body: some View {
        ZStack {
            LevitTheme.paper.opacity(0.86)
                .ignoresSafeArea()

            VStack(spacing: 14) {
                ProgressView()
                    .controlSize(.large)
                    .tint(LevitTheme.pink)
                Text("Cargando datos")
                    .font(.headline.weight(.black))
                    .foregroundStyle(LevitTheme.ink)
                Text(message)
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(LevitTheme.muted)
                    .multilineTextAlignment(.center)
            }
            .padding(24)
            .frame(maxWidth: 300)
            .background(LevitTheme.elevatedSurface, in: RoundedRectangle(cornerRadius: 20))
            .overlay(RoundedRectangle(cornerRadius: 20).stroke(LevitTheme.line))
        }
    }
}
