import SwiftUI

struct ScoresView: View {
    @EnvironmentObject private var store: JudgingStore
    let results: [RoutineResult]
    let onExportPDF: () -> Void

    @State private var selectedAcademy = allFilter
    @State private var selectedGenre = allFilter
    @State private var isRefreshingData = false

    private static let allFilter = "Todas"
    private var allFilter: String { Self.allFilter }

    private var academies: [String] {
        [allFilter] + uniqueValues(results.map(\.routine.academy))
    }

    private var genres: [String] {
        [allFilter] + uniqueValues(results.map(\.routine.genre))
    }

    private var filteredResults: [RoutineResult] {
        results.filter { result in
            let matchesAcademy = selectedAcademy == allFilter || result.routine.academy == selectedAcademy
            let matchesGenre = selectedGenre == allFilter || result.routine.genre == selectedGenre
            return matchesAcademy && matchesGenre
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            header
            filters
            rankingTable
        }
        .padding(30)
        .foregroundStyle(LevitTheme.ink)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(LevitTheme.paper.ignoresSafeArea())
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 12) {
                    Text("Ranking en vivo")
                        .font(.system(size: 31, weight: .black, design: .rounded))
                        .foregroundStyle(LevitTheme.ink)
                    Text("En vivo")
                        .font(.caption.weight(.black))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .foregroundStyle(LevitTheme.pink)
                        .background(LevitTheme.pink.opacity(0.14), in: Capsule())
                }
                Text("Actualizado hace 15 seg")
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(LevitTheme.muted)
            }

            Spacer()

            RefreshDataButton(isRefreshing: isRefreshingData) {
                Task { await refreshAdminData() }
            }
            .disabled(store.isLoadingBackendData)
            .opacity(store.isLoadingBackendData ? 0.58 : 1)

            Button(action: onExportPDF) {
                Label("Exportar PDF", systemImage: "doc.richtext")
                    .font(.callout.weight(.black))
                    .padding(.horizontal, 18)
                    .padding(.vertical, 13)
                    .foregroundStyle(.white)
                    .background(LevitTheme.pinkGradient, in: RoundedRectangle(cornerRadius: 13))
            }
            .buttonStyle(.plain)
        }
    }

    private var filters: some View {
        HStack(spacing: 12) {
            FilterCapsule(title: "General", isSelected: selectedAcademy == allFilter && selectedGenre == allFilter) {
                selectedAcademy = allFilter
                selectedGenre = allFilter
            }

            Picker("Academia", selection: $selectedAcademy) {
                ForEach(academies, id: \.self) { academy in
                    Text(academy).tag(academy)
                }
            }
            .pickerStyle(.menu)
            .tint(LevitTheme.ink)
            .frame(maxWidth: 260)
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .background(LevitTheme.softFill, in: Capsule())
            .overlay(Capsule().stroke(LevitTheme.line))

            Picker("Género", selection: $selectedGenre) {
                ForEach(genres, id: \.self) { genre in
                    Text(genre).tag(genre)
                }
            }
            .pickerStyle(.menu)
            .tint(LevitTheme.ink)
            .frame(maxWidth: 220)
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .background(LevitTheme.softFill, in: Capsule())
            .overlay(Capsule().stroke(LevitTheme.line))

            Spacer()

            Button {
                selectedAcademy = allFilter
                selectedGenre = allFilter
            } label: {
                Label("Filtros", systemImage: "slider.horizontal.3")
                    .font(.callout.weight(.bold))
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .foregroundStyle(LevitTheme.ink)
                    .background(LevitTheme.softFill, in: RoundedRectangle(cornerRadius: 13))
                    .overlay(RoundedRectangle(cornerRadius: 13).stroke(LevitTheme.line))
            }
            .buttonStyle(.plain)
        }
    }

    private var rankingTable: some View {
        ScrollView {
            VStack(spacing: 8) {
                HStack {
                    tableHeader("POS.", width: 58)
                    tableHeader("ACADEMIA", width: 330, alignment: .leading)
                    Spacer()
                    tableHeader("TOTAL", width: 120)
                    tableHeader("PENAL.", width: 92)
                    tableHeader("PROMEDIO", width: 120)
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 10)

                ForEach(Array(filteredResults.prefix(30).enumerated()), id: \.element.id) { index, result in
                    HStack(spacing: 16) {
                        Text("\(index + 1)")
                            .font(.callout.weight(.black))
                            .foregroundStyle(index < 3 ? LevitTheme.pink : LevitTheme.muted)
                            .frame(width: 34, height: 34)
                            .background(index < 3 ? LevitTheme.palePink : LevitTheme.softFill, in: Circle())
                            .frame(width: 58)

                        VStack(alignment: .leading, spacing: 4) {
                            Text(result.routine.academy.isEmpty ? result.routine.name : result.routine.academy)
                                .font(.headline.weight(.black))
                                .foregroundStyle(LevitTheme.ink)
                                .lineLimit(1)
                            Text("#\(result.routine.id) \(result.routine.name)")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(LevitTheme.muted)
                                .lineLimit(1)
                        }
                        .frame(width: 330, alignment: .leading)

                        Spacer()

                        Text(result.totalScore.formatted(.number.precision(.fractionLength(1))))
                            .font(.headline.monospacedDigit().weight(.bold))
                            .foregroundStyle(LevitTheme.ink)
                            .frame(width: 120)

                        Text(result.penalty != 0 ? result.penalty.formatted(.number.precision(.fractionLength(1))) : "-")
                            .font(.headline.monospacedDigit().weight(.bold))
                            .foregroundStyle(result.penalty != 0 ? LevitTheme.pink : LevitTheme.muted)
                            .frame(width: 92)

                        Text(result.total > 0 ? result.total.formatted(.number.precision(.fractionLength(1))) : "-")
                            .font(.headline.monospacedDigit().weight(.bold))
                            .foregroundStyle(LevitTheme.muted)
                            .frame(width: 120)
                    }
                    .padding(.horizontal, 18)
                    .padding(.vertical, 14)
                    .background(index == 0 ? LevitTheme.palePink : LevitTheme.solidSurface, in: RoundedRectangle(cornerRadius: 15))
                    .overlay(RoundedRectangle(cornerRadius: 15).stroke(LevitTheme.line))
                }
            }
            .padding(.bottom, 24)
        }
    }

    private func tableHeader(_ title: String, width: CGFloat, alignment: Alignment = .center) -> some View {
        Text(title)
            .font(.caption.weight(.black))
            .foregroundStyle(LevitTheme.muted)
            .frame(width: width, alignment: alignment)
    }

    private func uniqueValues(_ values: [String]) -> [String] {
        Array(Set(values.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }))
            .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    @MainActor
    private func refreshAdminData() async {
        guard !isRefreshingData else { return }
        isRefreshingData = true
        defer { isRefreshingData = false }

        do {
            try await store.refreshCurrentEvent()
            store.showOperationSuccess("Datos actualizados", message: "El ranking se actualizó con los puntajes del programa actual.")
        } catch {
            store.showOperationFailure("No se pudo actualizar", message: error.localizedDescription)
        }
    }
}

private struct FilterCapsule: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.callout.weight(.black))
                .padding(.horizontal, 18)
                .padding(.vertical, 11)
                .foregroundStyle(isSelected ? .white : LevitTheme.muted)
                .background(isSelected ? LevitTheme.pink : LevitTheme.softFill, in: Capsule())
                .overlay(Capsule().stroke(isSelected ? LevitTheme.pink.opacity(0.22) : LevitTheme.line))
        }
        .buttonStyle(.plain)
    }
}

private extension RoutineResult {
    var totalScore: Double {
        judgeTotals.reduce(0) { $0 + $1.total }
    }
}
