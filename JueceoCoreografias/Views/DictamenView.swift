import SwiftUI

struct DictamenView: View {
    @EnvironmentObject private var store: JudgingStore
    let results: [RoutineResult]
    @State private var isRefreshingData = false

    private var sections: [DictamenGenreSection] {
        DictamenBuilder.sections(from: results)
    }

    private var specialAwards: [SpecialAwardSummary] {
        store.specialAwardSummaries(for: store.selectedBlock)
    }

    private var totalRoutines: Int {
        sections.reduce(0) { total, section in
            total + section.rowCount
        }
    }

    private var completedCount: Int {
        results.filter { $0.aggregateTotal > 0 }.count
    }

    private var topScoringResult: RoutineResult? {
        results.max { lhs, rhs in
            if abs(lhs.aggregateTotal - rhs.aggregateTotal) < 0.0001 {
                let lhsNumber = DictamenBuilder.minimumParticipationNumber(in: lhs.routine.id)
                let rhsNumber = DictamenBuilder.minimumParticipationNumber(in: rhs.routine.id)
                if lhsNumber != rhsNumber {
                    return lhsNumber > rhsNumber
                }
                return lhs.routine.name.localizedCaseInsensitiveCompare(rhs.routine.name) == .orderedDescending
            }
            return lhs.aggregateTotal < rhs.aggregateTotal
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            header
            toolbar
            dictamenList
        }
        .padding(30)
        .foregroundStyle(LevitTheme.ink)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(LevitTheme.paper.ignoresSafeArea())
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 5) {
                Text("Dictamen final")
                    .font(.system(size: 31, weight: .black, design: .rounded))
                    .foregroundStyle(LevitTheme.ink)
                Text("Resultados oficiales de la hoja de jueceo")
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(LevitTheme.muted)
            }

            Spacer()

            RefreshDataButton(isRefreshing: isRefreshingData) {
                Task { await refreshAdminData() }
            }
            .disabled(store.isLoadingBackendData)
            .opacity(store.isLoadingBackendData ? 0.58 : 1)
            BlockPill()
        }
    }

    private var toolbar: some View {
        HStack(alignment: .center, spacing: 14) {
            summaryBar
            Spacer()
            if let topScoringResult {
                DictamenTopScoreCard(result: topScoringResult)
            }
        }
    }

    private var summaryBar: some View {
        HStack(spacing: 10) {
            DictamenMetricPill(icon: "rectangle.stack.fill", value: "\(sections.count)", title: "Géneros")
            DictamenMetricPill(icon: "square.grid.2x2.fill", value: "\(sections.reduce(0) { $0 + $1.categories.count })", title: "Categorías")
            DictamenMetricPill(icon: "checkmark.seal.fill", value: "\(completedCount)/\(totalRoutines)", title: "Calificadas")
        }
    }

    @ViewBuilder
    private var dictamenList: some View {
        if sections.isEmpty {
            DictamenEmptyState(
                title: "Sin dictamen",
                detail: "Cuando haya rutinas cargadas, las posiciones aparecerán acá."
            )
        } else {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 18) {
                    ForEach(sections) { section in
                        DictamenGenreTable(section: section, layout: .regular)
                    }
                    DictamenSpecialAwardsSection(awards: specialAwards, layout: .regular)
                }
                .padding(.bottom, 24)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }

    @MainActor
    private func refreshAdminData() async {
        guard !isRefreshingData else { return }
        isRefreshingData = true
        defer { isRefreshingData = false }

        do {
            try await store.refreshCurrentEvent()
            store.showOperationSuccess("Datos actualizados", message: "El dictamen final se actualizó con los puntajes del programa actual.")
        } catch {
            store.showOperationFailure("No se pudo actualizar", message: error.localizedDescription)
        }
    }
}

enum DictamenBuilder {
    static func sections(from results: [RoutineResult]) -> [DictamenGenreSection] {
        let usesCustomGenreOrder = !isBlockFour(results)

        return Dictionary(grouping: results) { result in
            clean(result.routine.genre, fallback: "SIN GÉNERO")
        }
        .map { genre, items in
            let categories = Dictionary(grouping: items) { result in
                categoryID(
                    genre: genre,
                    division: clean(result.routine.division, fallback: "SIN DATO"),
                    level: clean(result.routine.level, fallback: "SIN DATO"),
                    category: clean(result.routine.category, fallback: "SIN DATO")
                )
            }
            .compactMap { _, categoryItems -> DictamenCategorySection? in
                guard let sample = categoryItems.first?.routine else { return nil }
                let division = clean(sample.division, fallback: "SIN DATO")
                let level = clean(sample.level, fallback: "SIN DATO")
                let category = clean(sample.category, fallback: "SIN DATO")
                return DictamenCategorySection(
                    genre: genre,
                    division: division,
                    level: level,
                    category: category,
                    title: categoryTitle(division: division, level: level, category: category),
                    rows: rankedRows(categoryItems)
                )
            }
            .sorted(by: categoryOrder)

            return DictamenGenreSection(genre: genre, categories: categories)
        }
        .filter { !$0.categories.isEmpty }
        .sorted { compareGenres($0.genre, $1.genre, usesCustomOrder: usesCustomGenreOrder) }
    }

    private static func rankedRows(_ results: [RoutineResult]) -> [DictamenStandingRow] {
        let sortedResults = results.sorted {
            if abs($0.aggregateTotal - $1.aggregateTotal) < 0.0001 {
                return routineOrder($0.routine, $1.routine)
            }
            return $0.aggregateTotal > $1.aggregateTotal
        }

        if sortedResults.count == 1, let result = sortedResults.first {
            return [
                DictamenStandingRow(
                    result: result,
                    placement: CompetitionPlacement.solo(for: result.aggregateTotal)
                )
            ]
        }

        var rows: [DictamenStandingRow] = []
        var currentPosition = 0
        var previousScore: Double?

        for (index, result) in sortedResults.enumerated() {
            if previousScore == nil || abs(result.aggregateTotal - (previousScore ?? 0)) >= 0.0001 {
                currentPosition = index + 1
                previousScore = result.aggregateTotal
            }
            rows.append(DictamenStandingRow(result: result, placement: placement(for: currentPosition)))
        }

        return rows.sorted { lhs, rhs in
            routineOrder(lhs.result.routine, rhs.result.routine)
        }
    }

    private static func placement(for rank: Int) -> CompetitionPlacement {
        rank <= 3 ? .position(rank) : .participation
    }

    private static func categoryOrder(_ lhs: DictamenCategorySection, _ rhs: DictamenCategorySection) -> Bool {
        let lhsNumber = lhs.minimumParticipationNumber
        let rhsNumber = rhs.minimumParticipationNumber
        if lhsNumber != rhsNumber {
            return lhsNumber < rhsNumber
        }
        return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
    }

    private static func categoryTitle(division: String, level: String, category: String) -> String {
        var values: [String] = []
        for value in [division, level, category] {
            let cleaned = clean(value, fallback: "")
            guard !cleaned.isEmpty, cleaned.normalizedKey != "SIN DATO" else { continue }
            if !values.contains(where: { $0.normalizedKey == cleaned.normalizedKey }) {
                values.append(cleaned)
            }
        }
        return values.isEmpty ? "SIN DATO" : values.joined(separator: " ")
    }

    private static func categoryID(genre: String, division: String, level: String, category: String) -> String {
        [genre, division, level, category].map(\.normalizedKey).joined(separator: "|")
    }

    private static func compareGenres(_ lhs: String, _ rhs: String, usesCustomOrder: Bool) -> Bool {
        guard usesCustomOrder else {
            return lhs.localizedCaseInsensitiveCompare(rhs) == .orderedAscending
        }

        let lhsPriority = genrePriority(lhs)
        let rhsPriority = genrePriority(rhs)
        if lhsPriority != rhsPriority {
            return lhsPriority < rhsPriority
        }
        return lhs.localizedCaseInsensitiveCompare(rhs) == .orderedAscending
    }

    private static func genrePriority(_ genre: String) -> Int {
        let key = genre.stableRemoteID
        if key.contains("tela") {
            return 0
        }
        if key.contains("aro") {
            return 1
        }
        if key.contains("open") {
            return 2
        }
        return 3
    }

    private static func isBlockFour(_ results: [RoutineResult]) -> Bool {
        results.contains { result in
            [result.routine.blockID ?? "", result.routine.block].contains { value in
                isBlockFourIdentifier(value)
            }
        }
    }

    private static func isBlockFourIdentifier(_ value: String) -> Bool {
        let tokens = value.stableRemoteID.split(separator: "-")
        for index in tokens.indices where tokens[index] == "bloque" || tokens[index] == "block" {
            let nextIndex = tokens.index(after: index)
            if nextIndex < tokens.endIndex, tokens[nextIndex] == "4" {
                return true
            }
        }
        return false
    }

    private static func clean(_ value: String, fallback: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? fallback : trimmed
    }

    private static func routineOrder(_ lhs: Routine, _ rhs: Routine) -> Bool {
        let lhsNumber = minimumParticipationNumber(in: lhs.id)
        let rhsNumber = minimumParticipationNumber(in: rhs.id)
        if lhsNumber == rhsNumber {
            return lhs.id.localizedStandardCompare(rhs.id) == .orderedAscending
        }
        return lhsNumber < rhsNumber
    }

    static func minimumParticipationNumber(in value: String) -> Int {
        var numbers: [Int] = []
        var currentNumber = ""

        for scalar in value.unicodeScalars {
            if CharacterSet.decimalDigits.contains(scalar) {
                currentNumber.append(Character(scalar))
            } else if !currentNumber.isEmpty {
                numbers.append(Int(currentNumber) ?? Int.max)
                currentNumber.removeAll(keepingCapacity: true)
            }
        }

        if !currentNumber.isEmpty {
            numbers.append(Int(currentNumber) ?? Int.max)
        }

        return numbers.min() ?? Int.max
    }

    private static func searchableText(for result: RoutineResult) -> String {
        let routine = result.routine
        return [
            routine.id,
            routine.block,
            routine.name,
            routine.academy,
            routine.division,
            routine.genre,
            routine.level,
            routine.category,
            routine.choreographer,
            routine.participant ?? "",
            routine.state,
            result.aggregateTotal.formatted(.number.precision(.fractionLength(0...1)))
        ]
        .joined(separator: " ")
    }
}

struct DictamenGenreSection: Identifiable {
    let genre: String
    let categories: [DictamenCategorySection]

    var id: String { genre.normalizedKey }
    var rowCount: Int { categories.reduce(0) { $0 + $1.rows.count } }
}

struct DictamenCategorySection: Identifiable {
    let genre: String
    let division: String
    let level: String
    let category: String
    let title: String
    let rows: [DictamenStandingRow]

    var id: String {
        [genre, division, level, category].map(\.normalizedKey).joined(separator: "|")
    }

    var minimumParticipationNumber: Int {
        rows.map { DictamenBuilder.minimumParticipationNumber(in: $0.result.routine.id) }.min() ?? Int.max
    }
}

struct DictamenStandingRow: Identifiable {
    let result: RoutineResult
    let placement: CompetitionPlacement

    var id: String { result.id }
    var position: Int { placement.order }
}

struct DictamenTableLayout {
    let categoryWidth: CGFloat
    let stateWidth: CGFloat
    let academyWidth: CGFloat
    let choreographyWidth: CGFloat
    let scoreWidth: CGFloat
    let positionWidth: CGFloat
    let titleHeight: CGFloat
    let headerHeight: CGFloat
    let rowHeight: CGFloat
    let titleFontSize: CGFloat
    let headerFontSize: CGFloat
    let bodyFontSize: CGFloat
    let emphasisFontSize: CGFloat
    let categorySpacing: CGFloat

    var totalWidth: CGFloat {
        categoryWidth + stateWidth + academyWidth + choreographyWidth + scoreWidth + positionWidth
    }

    static let regular = DictamenTableLayout(
        categoryWidth: 140,
        stateWidth: 112,
        academyWidth: 270,
        choreographyWidth: 350,
        scoreWidth: 116,
        positionWidth: 150,
        titleHeight: 50,
        headerHeight: 64,
        rowHeight: 74,
        titleFontSize: 25,
        headerFontSize: 18,
        bodyFontSize: 17,
        emphasisFontSize: 19,
        categorySpacing: 24
    )

    static let compact = DictamenTableLayout(
        categoryWidth: 116,
        stateWidth: 76,
        academyWidth: 166,
        choreographyWidth: 220,
        scoreWidth: 78,
        positionWidth: 102,
        titleHeight: 42,
        headerHeight: 56,
        rowHeight: 68,
        titleFontSize: 18,
        headerFontSize: 12,
        bodyFontSize: 12,
        emphasisFontSize: 13,
        categorySpacing: 16
    )
}

struct DictamenGenreTable: View {
    let section: DictamenGenreSection
    let layout: DictamenTableLayout

    private var isCompact: Bool {
        layout.totalWidth < 900
    }

    var body: some View {
        VStack(alignment: .leading, spacing: isCompact ? 12 : 16) {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Género")
                        .font(.caption.weight(.black))
                        .foregroundStyle(.white.opacity(0.68))
                    Text(section.genre.uppercased())
                        .font(.system(size: layout.titleFontSize, weight: .black, design: .rounded))
                        .lineLimit(1)
                        .minimumScaleFactor(0.72)
                }

                Spacer()

                Label("\(section.rowCount)", systemImage: "person.2.fill")
                    .font(.callout.monospacedDigit().weight(.black))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(.white.opacity(0.14), in: Capsule())
            }
            .foregroundStyle(.white)
            .padding(.horizontal, isCompact ? 14 : 18)
            .padding(.vertical, isCompact ? 12 : 16)
            .background(LevitTheme.pinkGradient, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .shadow(color: LevitTheme.pink.opacity(0.18), radius: 16, x: 0, y: 8)

            VStack(alignment: .leading, spacing: layout.categorySpacing) {
                ForEach(section.categories) { category in
                    DictamenCategoryBlock(category: category, layout: layout)
                }
            }
        }
        .padding(isCompact ? 12 : 16)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct DictamenSpecialAwardsSection: View {
    let awards: [SpecialAwardSummary]
    let layout: DictamenTableLayout

    private var isCompact: Bool {
        layout.totalWidth < 900
    }

    var body: some View {
        VStack(alignment: .leading, spacing: isCompact ? 10 : 14) {
            HStack(alignment: .center, spacing: 12) {
                Image(systemName: "rosette")
                    .font(.headline.weight(.black))
                    .foregroundStyle(.white)
                    .frame(width: isCompact ? 34 : 40, height: isCompact ? 34 : 40)
                    .background(.white.opacity(0.16), in: Circle())

                VStack(alignment: .leading, spacing: 2) {
                    Text("Premios especiales")
                        .font(.system(size: isCompact ? 18 : 24, weight: .black, design: .rounded))
                    Text(awards.first?.blockName ?? "Bloque")
                        .font(.caption.weight(.black))
                        .foregroundStyle(.white.opacity(0.70))
                }

                Spacer()
            }
            .foregroundStyle(.white)
            .padding(.horizontal, isCompact ? 14 : 18)
            .padding(.vertical, isCompact ? 12 : 16)
            .background(LevitTheme.pinkGradient, in: RoundedRectangle(cornerRadius: 16, style: .continuous))

            VStack(spacing: isCompact ? 8 : 10) {
                ForEach(awards) { award in
                    DictamenSpecialAwardRow(award: award, isCompact: isCompact)
                }
            }
            .padding(isCompact ? 10 : 12)
            .background(LevitTheme.solidSurface, in: RoundedRectangle(cornerRadius: 15, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 15, style: .continuous).stroke(LevitTheme.line))
        }
        .padding(isCompact ? 12 : 16)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct DictamenSpecialAwardRow: View {
    let award: SpecialAwardSummary
    let isCompact: Bool

    var body: some View {
        HStack(alignment: .center, spacing: isCompact ? 10 : 14) {
            Image(systemName: award.category.systemImage)
                .font(.headline.weight(.black))
                .foregroundStyle(LevitTheme.pink)
                .frame(width: isCompact ? 38 : 46, height: isCompact ? 38 : 46)
                .background(LevitTheme.palePink, in: RoundedRectangle(cornerRadius: 13, style: .continuous))

            VStack(alignment: .leading, spacing: 5) {
                Text(award.category.title.uppercased())
                    .font(.caption.weight(.black))
                    .foregroundStyle(LevitTheme.muted)
                    .lineLimit(1)
                Text(award.displayValue)
                    .font(.system(size: isCompact ? 14 : 18, weight: .black, design: .rounded))
                    .foregroundStyle(award.isAssigned ? LevitTheme.ink : LevitTheme.muted)
                    .lineLimit(isCompact ? 2 : 1)
                    .minimumScaleFactor(0.74)

                if let routine = award.routine {
                    ViewThatFits(in: .horizontal) {
                        HStack(spacing: 7) {
                            DictamenInfoPill(text: display(routine.academy), systemImage: "building.2.fill")
                            DictamenInfoPill(text: display(routine.state).uppercased(), systemImage: "mappin.circle.fill")
                        }
                        VStack(alignment: .leading, spacing: 6) {
                            DictamenInfoPill(text: display(routine.academy), systemImage: "building.2.fill")
                            DictamenInfoPill(text: display(routine.state).uppercased(), systemImage: "mappin.circle.fill")
                        }
                    }
                }
            }

            Spacer(minLength: 8)
        }
        .padding(isCompact ? 10 : 12)
        .background(LevitTheme.softFill, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(LevitTheme.line))
    }

    private func display(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "SIN DATO" : trimmed
    }
}

private struct DictamenHeaderRow: View {
    let layout: DictamenTableLayout

    var body: some View {
        HStack(spacing: 0) {
            DictamenCell(text: "CATEGORIA", width: layout.categoryWidth, height: layout.headerHeight, fill: tableHeaderFill, fontSize: layout.headerFontSize, weight: .black, lineLimit: 2)
            DictamenCell(text: "ESTADO", width: layout.stateWidth, height: layout.headerHeight, fill: tableHeaderFill, fontSize: layout.headerFontSize, weight: .black, lineLimit: 2)
            DictamenCell(text: "ACADEMIA", width: layout.academyWidth, height: layout.headerHeight, fill: tableHeaderFill, fontSize: layout.headerFontSize, weight: .black, lineLimit: 2)
            DictamenCell(text: "COREOGRAFÍA", width: layout.choreographyWidth, height: layout.headerHeight, fill: tableHeaderFill, fontSize: layout.headerFontSize, weight: .black, lineLimit: 2)
            DictamenCell(text: "PUNTAJE", width: layout.scoreWidth, height: layout.headerHeight, fill: tableHeaderFill, fontSize: layout.headerFontSize, weight: .black, lineLimit: 2)
            DictamenCell(text: "TABLA DE\nPOSICIONES", width: layout.positionWidth, height: layout.headerHeight, fill: tableHeaderFill, fontSize: layout.headerFontSize, weight: .black, lineLimit: 2)
        }
    }
}

private struct DictamenCategoryBlock: View {
    let category: DictamenCategorySection
    let layout: DictamenTableLayout

    private var isCompact: Bool {
        layout.totalWidth < 900
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(category.title.uppercased())
                    .font(.system(size: layout.emphasisFontSize, weight: .black, design: .rounded))
                    .lineLimit(2)
                    .minimumScaleFactor(0.72)

                Spacer()

                Text("\(category.rows.count) rutinas")
                    .font(.caption.monospacedDigit().weight(.black))
                    .foregroundStyle(LevitTheme.muted)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(LevitTheme.softFill, in: Capsule())
            }

            VStack(alignment: .leading, spacing: isCompact ? 8 : 10) {
                ForEach(Array(category.rows.enumerated()), id: \.element.id) { index, row in
                    DictamenStandingRowView(row: row, rowIndex: index, layout: layout)
                }
            }
        }
        .padding(isCompact ? 10 : 12)
        .background(LevitTheme.solidSurface, in: RoundedRectangle(cornerRadius: 15, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 15, style: .continuous).stroke(LevitTheme.line))
    }
}

private struct DictamenStandingRowView: View {
    let row: DictamenStandingRow
    let rowIndex: Int
    let layout: DictamenTableLayout

    private var isCompact: Bool {
        layout.totalWidth < 900
    }

    private var routine: Routine {
        row.result.routine
    }

    var body: some View {
        HStack(alignment: .center, spacing: isCompact ? 10 : 14) {
            DictamenParticipationBadge(text: "#\(display(routine.id))", isCompact: isCompact)

            VStack(alignment: .leading, spacing: isCompact ? 7 : 8) {
                Text(display(routine.name))
                    .font(.system(size: layout.emphasisFontSize, weight: .black, design: .rounded))
                    .lineLimit(isCompact ? 2 : 1)
                    .minimumScaleFactor(0.75)

                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 7) {
                        DictamenInfoPill(text: display(routine.academy), systemImage: "building.2.fill")
                        DictamenInfoPill(text: display(routine.state).uppercased(), systemImage: "mappin.circle.fill")
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        DictamenInfoPill(text: display(routine.academy), systemImage: "building.2.fill")
                        DictamenInfoPill(text: display(routine.state).uppercased(), systemImage: "mappin.circle.fill")
                    }
                }
            }

            Spacer(minLength: 8)

            HStack(alignment: .center, spacing: isCompact ? 16 : 24) {
                DictamenScoreBadge(text: scoreText, isCompact: isCompact)
                DictamenRankBadge(placement: row.placement, size: isCompact ? 40 : 48)
            }
        }
        .padding(isCompact ? 10 : 12)
        .foregroundStyle(LevitTheme.ink)
        .background(row.placement.isFirstPlace ? LevitTheme.palePink.opacity(0.74) : LevitTheme.softFill, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(row.placement.isFirstPlace ? LevitTheme.pink.opacity(0.20) : LevitTheme.line))
    }

    private var scoreText: String {
        row.result.aggregateTotal.formatted(.number.precision(.fractionLength(0...1)))
    }

    private func display(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "SIN DATO" : trimmed
    }
}

private struct DictamenParticipationBadge: View {
    let text: String
    let isCompact: Bool

    var body: some View {
        Text(text)
            .font(.system(size: isCompact ? 14 : 16, weight: .black, design: .rounded).monospacedDigit())
            .lineLimit(1)
            .minimumScaleFactor(0.68)
            .foregroundStyle(LevitTheme.pink)
            .frame(width: isCompact ? 54 : 66, height: isCompact ? 38 : 44)
            .background(LevitTheme.palePink, in: RoundedRectangle(cornerRadius: isCompact ? 12 : 14, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: isCompact ? 12 : 14, style: .continuous).stroke(LevitTheme.pink.opacity(0.18)))
    }
}

private struct DictamenRankBadge: View {
    let placement: CompetitionPlacement
    let size: CGFloat

    var body: some View {
        Text(placement.shortLabel)
            .font(.system(size: placement.isParticipation ? size * 0.24 : size * 0.34, weight: .black, design: .rounded).monospacedDigit())
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .foregroundStyle(.white)
            .frame(width: badgeWidth, height: size)
            .background(badgeFill, in: RoundedRectangle(cornerRadius: size / 2, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: size / 2, style: .continuous).stroke(.white.opacity(0.24), lineWidth: 1))
            .shadow(color: LevitTheme.pink.opacity(0.22), radius: 10, x: 0, y: 6)
    }

    private var badgeWidth: CGFloat {
        placement.isParticipation ? size * 1.32 : size
    }

    private var badgeFill: LinearGradient {
        LevitTheme.pinkGradient
    }
}

private struct DictamenInfoPill: View {
    let text: String
    let systemImage: String

    var body: some View {
        Label(text.uppercased(), systemImage: systemImage)
            .font(.caption.weight(.black))
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .foregroundStyle(LevitTheme.muted)
            .padding(.horizontal, 9)
            .padding(.vertical, 6)
            .background(LevitTheme.solidSurface.opacity(0.72), in: Capsule())
            .overlay(Capsule().stroke(LevitTheme.line))
    }
}

private struct DictamenScoreBadge: View {
    let text: String
    let isCompact: Bool

    var body: some View {
        VStack(alignment: .center, spacing: 1) {
            Text(text)
                .font(.system(size: isCompact ? 18 : 22, weight: .black, design: .rounded).monospacedDigit())
                .lineLimit(1)
                .minimumScaleFactor(0.72)
                .multilineTextAlignment(.center)
            Text("pts")
                .font(.caption2.weight(.black))
                .foregroundStyle(LevitTheme.muted)
                .multilineTextAlignment(.center)
        }
        .frame(width: isCompact ? 54 : 68, alignment: .center)
    }
}

private struct DictamenCell: View {
    let text: String
    let width: CGFloat
    let height: CGFloat
    let fill: Color
    let fontSize: CGFloat
    let weight: Font.Weight
    var lineLimit = 1
    var textColor: Color = LevitTheme.ink
    var borderColor: Color = tableStroke
    var monospacedDigit = false

    var body: some View {
        Text(text)
            .font(font)
            .multilineTextAlignment(.center)
            .lineLimit(lineLimit)
            .minimumScaleFactor(0.68)
            .foregroundStyle(textColor)
            .padding(.horizontal, 8)
            .frame(width: width, height: height)
            .background(fill)
            .overlay(Rectangle().stroke(borderColor, lineWidth: 0.72))
    }

    private var font: Font {
        let font = Font.system(size: fontSize, weight: weight, design: .rounded)
        return monospacedDigit ? font.monospacedDigit() : font
    }
}

private struct DictamenScoreCell: View {
    let text: String
    let width: CGFloat
    let height: CGFloat
    let fill: Color
    let fontSize: CGFloat

    var body: some View {
        ZStack {
            fill
            Text(text)
                .font(.system(size: fontSize, weight: .black, design: .rounded).monospacedDigit())
                .foregroundStyle(LevitTheme.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
                .padding(.horizontal, 8)
                .frame(width: min(width - 14, 54), height: min(height - 22, 30))
                .background(LevitTheme.solidSurface.opacity(0.68), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(LevitTheme.line))
        }
        .frame(width: width, height: height)
        .overlay(Rectangle().stroke(tableStroke, lineWidth: 0.72))
    }
}

private struct DictamenPositionCell: View {
    let placement: CompetitionPlacement
    let width: CGFloat
    let height: CGFloat
    let fill: Color
    let fontSize: CGFloat

    var body: some View {
        ZStack {
            fill
            Text(placement.shortLabel)
                .font(.system(size: placement.isParticipation ? fontSize * 0.78 : fontSize, weight: .black, design: .rounded).monospacedDigit())
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
                .padding(.horizontal, 10)
                .frame(width: min(width - 18, placement.isParticipation ? 74 : 54), height: min(height - 22, 30))
                .background(badgeFill, in: Capsule())
                .overlay(Capsule().stroke(.white.opacity(0.28)))
        }
        .frame(width: width, height: height)
        .overlay(Rectangle().stroke(tableStroke, lineWidth: 0.72))
    }

    private var badgeFill: LinearGradient {
        LevitTheme.pinkGradient
    }
}

private struct DictamenMetricPill: View {
    let icon: String
    let value: String
    let title: String

    var body: some View {
        Label {
            HStack(spacing: 5) {
                Text(value)
                    .font(.callout.monospacedDigit().weight(.black))
                Text(title)
                    .font(.callout.weight(.bold))
                    .foregroundStyle(LevitTheme.muted)
            }
        } icon: {
            Image(systemName: icon)
                .foregroundStyle(LevitTheme.pink)
        }
        .padding(.horizontal, 13)
        .padding(.vertical, 10)
        .foregroundStyle(LevitTheme.ink)
        .background(LevitTheme.solidSurface, in: Capsule())
        .overlay(Capsule().stroke(LevitTheme.line))
    }
}

private struct DictamenTopScoreCard: View {
    let result: RoutineResult

    private var scoreText: String {
        result.aggregateTotal.formatted(.number.precision(.fractionLength(0...1)))
    }

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: "crown.fill")
                .font(.system(size: 18, weight: .black))
                .foregroundStyle(LevitTheme.pink)
                .frame(width: 44, height: 44)
                .background(LevitTheme.palePink, in: RoundedRectangle(cornerRadius: 14, style: .continuous))

            VStack(alignment: .leading, spacing: 3) {
                Text("Mayor puntaje")
                    .font(.caption.weight(.black))
                    .foregroundStyle(LevitTheme.muted)
                    .lineLimit(1)
                Text(result.routine.name)
                    .font(.system(size: 18, weight: .black, design: .rounded))
                    .foregroundStyle(LevitTheme.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
            }

            Spacer(minLength: 18)

            VStack(alignment: .trailing, spacing: 0) {
                Text(scoreText)
                    .font(.system(size: 26, weight: .black, design: .rounded).monospacedDigit())
                    .foregroundStyle(LevitTheme.pink)
                    .lineLimit(1)
                Text("pts")
                    .font(.caption2.weight(.black))
                    .foregroundStyle(LevitTheme.muted)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(width: 420, alignment: .leading)
        .background(LevitTheme.solidSurface, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).stroke(LevitTheme.line))
    }
}

private struct DictamenEmptyState: View {
    let title: String
    let detail: String

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: "trophy")
                .font(.title2.weight(.bold))
                .foregroundStyle(LevitTheme.muted)
                .frame(width: 48, height: 48)
                .background(LevitTheme.softFill, in: Circle())

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline.weight(.black))
                Text(detail)
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(LevitTheme.muted)
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(LevitTheme.solidSurface, in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(LevitTheme.line))
    }
}

private var tableStroke: Color {
    LevitTheme.ink.opacity(0.38)
}

private var tableHeaderFill: Color {
    LevitTheme.palePink.opacity(0.48)
}
