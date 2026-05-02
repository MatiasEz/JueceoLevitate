import SwiftUI

struct DictamenView: View {
    @EnvironmentObject private var store: JudgingStore
    let results: [RoutineResult]
    let onExportPDF: () -> Void

    @State private var selectedGroupID: String?
    @State private var presentedGroup: DictamenGroup?

    private var dictamenGroups: [DictamenGroup] {
        Dictionary(grouping: results) { result in
            DictamenGroup.id(
                genre: emptyFallback(result.routine.genre),
                age: emptyFallback(result.routine.division),
                amount: emptyFallback(result.routine.category)
            )
        }
        .compactMap { _, items -> DictamenGroup? in
            guard let sample = items.first?.routine else { return nil }
            return DictamenGroup(
                genre: emptyFallback(sample.genre),
                age: emptyFallback(sample.division),
                amount: emptyFallback(sample.category),
                results: sortedResults(items)
            )
        }
        .sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
    }

    private var selectedGroup: DictamenGroup? {
        if let selectedGroupID,
           let group = dictamenGroups.first(where: { $0.id == selectedGroupID }) {
            return group
        }
        return dictamenGroups.first
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            header
            selectedGroupSummary
            podiumView(group: selectedGroup)
            actionButtons
            groupsGrid
        }
        .padding(30)
        .background(LevitTheme.paper)
        .fullScreenCover(item: $presentedGroup) { group in
            FullScreenPodiumView(group: group)
        }
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 5) {
                Text("Dictamen final")
                    .font(.system(size: 31, weight: .black, design: .rounded))
                    .foregroundStyle(LevitTheme.ink)
                Text("Resultados oficiales por Genero · Edad · Cantidad")
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(LevitTheme.muted)
            }

            Spacer()

            EventPill()
        }
    }

    @ViewBuilder
    private var selectedGroupSummary: some View {
        if let selectedGroup {
            HStack(spacing: 12) {
                Label("Categoria seleccionada", systemImage: "trophy.fill")
                    .font(.callout.weight(.black))
                    .foregroundStyle(LevitTheme.pink)

                Text(selectedGroup.title)
                    .font(.title3.weight(.black))
                    .foregroundStyle(LevitTheme.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)

                Spacer()

                Text("\(selectedGroup.completedCount) / \(selectedGroup.results.count) calificadas")
                    .font(.callout.monospacedDigit().weight(.bold))
                    .foregroundStyle(LevitTheme.muted)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 14)
            .background(LevitTheme.elevatedSurface, in: RoundedRectangle(cornerRadius: 18))
            .overlay(RoundedRectangle(cornerRadius: 18).stroke(LevitTheme.line))
        }
    }

    private func podiumView(group: DictamenGroup?) -> some View {
        let podium = group?.podium ?? []
        return HStack(alignment: .bottom, spacing: 18) {
            PodiumCard(result: podium.indices.contains(1) ? podium[1] : nil, title: "Segundo lugar", rank: 2, height: 210, color: LevitTheme.silverPodium)
            PodiumCard(result: podium.indices.contains(0) ? podium[0] : nil, title: "Primer lugar", rank: 1, height: 270, color: LevitTheme.pink)
            PodiumCard(result: podium.indices.contains(2) ? podium[2] : nil, title: "Tercer lugar", rank: 3, height: 210, color: LevitTheme.bronzePodium)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 10)
    }

    private var actionButtons: some View {
        VStack(spacing: 12) {
            Button {
                presentedGroup = selectedGroup
            } label: {
                Label("Mostrar podio en pantalla completa", systemImage: "trophy")
                    .font(.headline.weight(.black))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .foregroundStyle(.white)
                    .background(LevitTheme.pinkGradient, in: RoundedRectangle(cornerRadius: 17))
            }
            .buttonStyle(.plain)
            .disabled(dictamenGroups.isEmpty)
            .opacity(dictamenGroups.isEmpty ? 0.45 : 1)

            Button(action: onExportPDF) {
                Label("Generar y exportar resultados", systemImage: "doc.richtext")
                    .font(.headline.weight(.bold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 15)
                    .foregroundStyle(LevitTheme.ink)
                    .background(LevitTheme.solidSurface, in: RoundedRectangle(cornerRadius: 17))
                    .overlay(RoundedRectangle(cornerRadius: 17).stroke(LevitTheme.line))
            }
            .buttonStyle(.plain)
        }
    }

    private var groupsGrid: some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 300), spacing: 14)], spacing: 14) {
                ForEach(dictamenGroups) { group in
                    Button {
                        selectedGroupID = group.id
                        presentedGroup = group
                    } label: {
                        DictamenGroupCard(
                            group: group,
                            isSelected: isSelected(group)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.bottom, 24)
        }
    }

    private func sortedResults(_ items: [RoutineResult]) -> [RoutineResult] {
        items.sorted {
            if $0.total == $1.total {
                return (Int($0.routine.id) ?? 0) < (Int($1.routine.id) ?? 0)
            }
            return $0.total > $1.total
        }
    }

    private func isSelected(_ group: DictamenGroup) -> Bool {
        group.id == (selectedGroup?.id ?? dictamenGroups.first?.id ?? "")
    }

    private func emptyFallback(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "SIN DATO" : value
    }
}

private struct DictamenGroup: Identifiable {
    let genre: String
    let age: String
    let amount: String
    let results: [RoutineResult]

    var id: String { Self.id(genre: genre, age: age, amount: amount) }
    var title: String { "\(genre) · \(age) · \(amount)" }
    var completedCount: Int { results.filter { $0.total > 0 }.count }
    var podium: [RoutineResult] { Array(results.filter { $0.total > 0 }.prefix(3)) }

    static func id(genre: String, age: String, amount: String) -> String {
        [genre, age, amount].map(\.normalizedKey).joined(separator: "|")
    }
}

private struct DictamenGroupCard: View {
    let group: DictamenGroup
    let isSelected: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 10) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(group.genre)
                        .font(.headline.weight(.black))
                        .foregroundStyle(LevitTheme.ink)
                        .lineLimit(1)
                    HStack(spacing: 6) {
                        LevitTag(group.age)
                        LevitTag(group.amount)
                    }
                }

                Spacer()

                Image(systemName: isSelected ? "trophy.fill" : "arrow.up.forward")
                    .font(.headline.weight(.black))
                    .foregroundStyle(isSelected ? LevitTheme.pink : LevitTheme.muted)
            }

            VStack(spacing: 8) {
                ForEach(Array(group.results.prefix(3).enumerated()), id: \.element.id) { index, result in
                    HStack(spacing: 12) {
                        Text("\(index + 1)")
                            .font(.caption.weight(.black))
                            .foregroundStyle(index == 0 ? .white : LevitTheme.ink)
                            .frame(width: 28, height: 28)
                            .background(index == 0 ? LevitTheme.pink : LevitTheme.softFill, in: Circle())

                        VStack(alignment: .leading, spacing: 2) {
                            Text(result.routine.academy.isEmpty ? result.routine.name : result.routine.academy)
                                .font(.callout.weight(.bold))
                                .foregroundStyle(LevitTheme.ink)
                                .lineLimit(1)
                            Text("#\(result.routine.id) \(result.routine.name)")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(LevitTheme.muted)
                                .lineLimit(1)
                        }

                        Spacer()

                        Text(result.total > 0 ? result.total.formatted(.number.precision(.fractionLength(2))) : "-")
                            .font(.headline.monospacedDigit().weight(.black))
                            .foregroundStyle(LevitTheme.ink)
                    }
                }
            }

            Spacer(minLength: 0)

            HStack {
                Text("\(group.completedCount) / \(group.results.count) calificadas")
                    .font(.caption.monospacedDigit().weight(.bold))
                    .foregroundStyle(LevitTheme.muted)
                Spacer()
                Text("Ver podio")
                    .font(.caption.weight(.black))
                    .foregroundStyle(LevitTheme.pink)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, minHeight: 190, alignment: .topLeading)
        .background(isSelected ? LevitTheme.palePink.opacity(0.76) : LevitTheme.solidSurface, in: RoundedRectangle(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(isSelected ? LevitTheme.pink.opacity(0.34) : LevitTheme.line, lineWidth: isSelected ? 1.4 : 1))
        .shadow(color: .black.opacity(isSelected ? 0.08 : 0.035), radius: 18, x: 0, y: 10)
    }
}

private struct FullScreenPodiumView: View {
    @Environment(\.dismiss) private var dismiss
    let group: DictamenGroup

    var body: some View {
        GeometryReader { proxy in
            let podium = group.podium
            let winnerHeight = min(430, proxy.size.height * 0.48)
            let sideHeight = min(330, proxy.size.height * 0.36)

            VStack(spacing: 24) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Dictamen final")
                            .font(.title3.weight(.black))
                            .foregroundStyle(.white.opacity(0.58))
                        Text(group.title)
                            .font(.system(size: 46, weight: .black, design: .rounded))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                            .minimumScaleFactor(0.55)
                        HStack(spacing: 8) {
                            LevitTag(group.genre, dark: true)
                            LevitTag(group.age, dark: true)
                            LevitTag(group.amount, dark: true)
                        }
                    }

                    Spacer()

                    Button {
                        dismiss()
                    } label: {
                        Label("Cerrar", systemImage: "xmark")
                            .font(.headline.weight(.black))
                            .padding(.horizontal, 18)
                            .padding(.vertical, 12)
                            .foregroundStyle(.white.opacity(0.84))
                            .background(.white.opacity(0.10), in: Capsule())
                    }
                    .buttonStyle(.plain)
                }

                Spacer(minLength: 10)

                HStack(alignment: .bottom, spacing: 28) {
                    FullScreenPodiumCard(
                        result: podium.indices.contains(1) ? podium[1] : nil,
                        title: "Segundo lugar",
                        rank: 2,
                        height: sideHeight,
                        color: LevitTheme.silverPodium
                    )

                    FullScreenPodiumCard(
                        result: podium.indices.contains(0) ? podium[0] : nil,
                        title: "Primer lugar",
                        rank: 1,
                        height: winnerHeight,
                        color: LevitTheme.pink
                    )

                    FullScreenPodiumCard(
                        result: podium.indices.contains(2) ? podium[2] : nil,
                        title: "Tercer lugar",
                        rank: 3,
                        height: sideHeight,
                        color: LevitTheme.bronzePodium
                    )
                }
                .frame(maxWidth: 1120)

                Spacer(minLength: 0)

                Text("\(group.completedCount) de \(group.results.count) coreografias calificadas")
                    .font(.headline.monospacedDigit().weight(.bold))
                    .foregroundStyle(.white.opacity(0.58))
            }
            .padding(.horizontal, 48)
            .padding(.vertical, 36)
            .frame(width: proxy.size.width, height: proxy.size.height)
            .background(
                LinearGradient(
                    colors: [LevitTheme.dark, Color(red: 0.065, green: 0.075, blue: 0.095), Color(red: 0.035, green: 0.043, blue: 0.060)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .overlay(alignment: .topTrailing) {
                RadialGradient(colors: [LevitTheme.pink.opacity(0.22), .clear], center: .topTrailing, startRadius: 40, endRadius: 520)
                    .allowsHitTesting(false)
            }
        }
        .ignoresSafeArea()
    }
}

private struct FullScreenPodiumCard: View {
    let result: RoutineResult?
    let title: String
    let rank: Int
    let height: CGFloat
    let color: Color

    private var isWinner: Bool { rank == 1 }

    var body: some View {
        VStack(spacing: 18) {
            Text(title)
                .font(.title3.weight(.black))
                .foregroundStyle(isWinner ? .white.opacity(0.76) : LevitTheme.muted)

            ZStack {
                Circle()
                    .fill(isWinner ? Color.yellow.opacity(0.96) : LevitTheme.softFill)
                    .frame(width: isWinner ? 74 : 60, height: isWinner ? 74 : 60)
                Text("\(rank)")
                    .font(.system(size: isWinner ? 31 : 25, weight: .black, design: .rounded))
                    .foregroundStyle(isWinner ? LevitTheme.pink : LevitTheme.muted)
            }

            Spacer()

            VStack(spacing: 10) {
                Text(result?.routine.academy ?? "SIN RESULTADO")
                    .font(.system(size: isWinner ? 30 : 24, weight: .black, design: .rounded))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(isWinner ? .white : LevitTheme.ink)
                    .lineLimit(3)
                    .minimumScaleFactor(0.65)

                Text(result.map { "#\($0.routine.id) \($0.routine.name)" } ?? "Sin coreografia")
                    .font(.headline.weight(.bold))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(isWinner ? .white.opacity(0.70) : LevitTheme.muted)
                    .lineLimit(2)
                    .minimumScaleFactor(0.7)
            }

            Text(result.map { $0.total.formatted(.number.precision(.fractionLength(1))) } ?? "-")
                .font(.system(size: isWinner ? 46 : 36, weight: .black, design: .rounded).monospacedDigit())
                .foregroundStyle(isWinner ? .white : LevitTheme.ink)
        }
        .padding(isWinner ? 30 : 24)
        .frame(maxWidth: 330, minHeight: height, maxHeight: height)
        .background(isWinner ? LevitTheme.pinkGradient : LinearGradient(colors: [color, color], startPoint: .top, endPoint: .bottom), in: RoundedRectangle(cornerRadius: 26))
        .overlay(RoundedRectangle(cornerRadius: 26).stroke(isWinner ? .white.opacity(0.26) : .white.opacity(0.08)))
        .shadow(color: isWinner ? LevitTheme.pink.opacity(0.30) : .black.opacity(0.18), radius: 30, x: 0, y: 18)
    }
}

private struct PodiumCard: View {
    let result: RoutineResult?
    let title: String
    let rank: Int
    let height: CGFloat
    let color: Color

    private var isWinner: Bool { rank == 1 }

    var body: some View {
        VStack(spacing: 14) {
            Text(title)
                .font(.callout.weight(.black))
                .foregroundStyle(isWinner ? .white.opacity(0.74) : LevitTheme.muted)

            ZStack {
                Circle()
                    .fill(isWinner ? Color.yellow.opacity(0.95) : LevitTheme.softFill)
                    .frame(width: 46, height: 46)
                Text("\(rank)")
                    .font(.headline.weight(.black))
                    .foregroundStyle(isWinner ? LevitTheme.pink : LevitTheme.muted)
            }

            Spacer()

            Text(result?.routine.academy ?? "SIN RESULTADO")
                .font(.headline.weight(.black))
                .multilineTextAlignment(.center)
                .foregroundStyle(isWinner ? .white : LevitTheme.ink)
                .lineLimit(3)
                .minimumScaleFactor(0.75)

            Text(result.map { $0.total.formatted(.number.precision(.fractionLength(1))) } ?? "-")
                .font(.title2.monospacedDigit().weight(.black))
                .foregroundStyle(isWinner ? .white : LevitTheme.ink)
        }
        .padding(20)
        .frame(maxWidth: 230, minHeight: height, maxHeight: height)
        .background(isWinner ? LevitTheme.pinkGradient : LinearGradient(colors: [color, color], startPoint: .top, endPoint: .bottom), in: RoundedRectangle(cornerRadius: 20))
        .overlay(RoundedRectangle(cornerRadius: 20).stroke(isWinner ? .white.opacity(0.28) : LevitTheme.line))
        .shadow(color: isWinner ? LevitTheme.pink.opacity(0.24) : .black.opacity(0.04), radius: 24, x: 0, y: 12)
    }
}
