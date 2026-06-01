import SwiftUI
import JueceoCore

struct FavoritesView: View {
    @EnvironmentObject private var store: JudgingStore
    @State private var isRefreshingData = false
    @State private var savingSpecialAward: SpecialAwardCategory?
    @State private var specialAwardDrafts: [SpecialAwardCategory: String] = [:]

    private var favorites: [FavoriteSelectionSummary] {
        store.favoriteSummaries
    }

    private var rankingBlocks: [FavoriteRankingBlock] {
        store.favoriteRankingBlocks
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                header
                summaryGrid
                specialAwardsPanel
                favoritesContent
            }
            .padding(.horizontal, 34)
            .padding(.vertical, 28)
            .frame(maxWidth: 1240, alignment: .leading)
        }
        .background(LevitTheme.paper.ignoresSafeArea())
        .foregroundStyle(LevitTheme.ink)
        .onAppear {
            syncSpecialAwardDrafts()
        }
        .onChange(of: store.selectedBlock?.id ?? "") { _, _ in
            syncSpecialAwardDrafts()
        }
        .onChange(of: store.specialAwardManualValues) { _, _ in
            syncSpecialAwardDrafts()
        }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 22) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Favoritos")
                    .font(.system(size: 38, weight: .black, design: .rounded))
                    .foregroundStyle(LevitTheme.ink)
                Text(store.selectedBlock?.name ?? "Todos los bloques")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(LevitTheme.muted)
                    .lineLimit(1)
            }

            Spacer()

            HStack(spacing: 18) {
                RefreshDataButton(isRefreshing: isRefreshingData) {
                    Task { await refreshAdminData() }
                }
                .disabled(store.isLoadingBackendData)
                .opacity(store.isLoadingBackendData ? 0.58 : 1)
                EventPill()
                BlockPill()
                SyncPill(status: store.syncStatus, pendingCount: store.pendingSyncCount)
            }
        }
    }

    private var summaryGrid: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 210), spacing: 14)], spacing: 14) {
            FavoriteMetricCard(
                icon: "star.fill",
                value: "\(favorites.count)",
                label: "Total",
                detail: store.pendingSyncCount == 0 ? "Sin pendientes" : "\(store.pendingSyncCount) por subir"
            )

            ForEach(FavoriteCategory.allCases) { category in
                FavoriteMetricCard(
                    icon: category.systemImage,
                    value: "\(favorites.filter { $0.category == category }.count)",
                    label: category.title,
                    detail: "Favoritos marcados"
                )
            }
        }
    }

    @ViewBuilder
    private var favoritesContent: some View {
        if rankingBlocks.isEmpty {
            emptyState
        } else {
            VStack(alignment: .leading, spacing: 18) {
                ForEach(rankingBlocks) { block in
                    FavoriteRankingBlockSection(block: block)
                }
            }
        }
    }

    private var specialAwardsPanel: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 10) {
                Image(systemName: "rosette")
                    .font(.headline.weight(.black))
                    .foregroundStyle(LevitTheme.pink)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Premios especiales")
                        .font(.title3.weight(.black))
                    Text(store.selectedBlock?.name ?? "Seleccioná un bloque")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(LevitTheme.muted)
                }
                Spacer()
            }

            LazyVGrid(columns: specialAwardColumns, spacing: 12) {
                ForEach(SpecialAwardCategory.manualEntryCases) { category in
                    FavoriteManualSpecialAwardField(
                        category: category,
                        value: specialAwardDraftBinding(for: category),
                        currentValue: store.specialAwardManualValue(for: category),
                        isSaving: savingSpecialAward == category,
                        onSave: {
                            Task { await updateManualSpecialAward(category, value: specialAwardDraftValue(for: category)) }
                        },
                        onClear: {
                            specialAwardDrafts[category] = ""
                            Task { await updateManualSpecialAward(category, value: nil) }
                        }
                    )
                    .disabled(savingSpecialAward != nil || store.selectedBlock == nil)
                    .opacity(savingSpecialAward != nil || store.selectedBlock == nil ? 0.58 : 1)
                }
            }
        }
        .padding(20)
        .background(LevitTheme.surface, in: RoundedRectangle(cornerRadius: 22))
        .overlay(RoundedRectangle(cornerRadius: 22).stroke(LevitTheme.cardStroke))
        .shadow(color: .black.opacity(0.045), radius: 22, x: 0, y: 12)
    }

    private var specialAwardColumns: [GridItem] {
        [
            GridItem(.flexible(minimum: 420), spacing: 12),
            GridItem(.flexible(minimum: 420), spacing: 12)
        ]
    }

    private var emptyState: some View {
        HStack(spacing: 14) {
            Image(systemName: "star.slash")
                .font(.title3.weight(.bold))
                .foregroundStyle(LevitTheme.muted)
                .frame(width: 48, height: 48)
                .background(LevitTheme.softFill, in: Circle())

            VStack(alignment: .leading, spacing: 4) {
                Text("Todavía no hay favoritos")
                    .font(.headline.weight(.black))
                Text("Cuando los jueces marquen vestuario, coreografía o música, los votos van a aparecer acá.")
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(LevitTheme.muted)
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(LevitTheme.surface, in: RoundedRectangle(cornerRadius: 22))
        .overlay(RoundedRectangle(cornerRadius: 22).stroke(LevitTheme.cardStroke))
        .shadow(color: .black.opacity(0.045), radius: 22, x: 0, y: 12)
    }

    @MainActor
    private func refreshAdminData() async {
        guard !isRefreshingData else { return }
        isRefreshingData = true
        defer { isRefreshingData = false }

        do {
            try await store.refreshCurrentEvent()
            store.showOperationSuccess("Datos actualizados", message: "Los favoritos se actualizaron con la información del programa actual.")
        } catch {
            store.showOperationFailure("No se pudo actualizar", message: error.localizedDescription)
        }
    }

    @MainActor
    private func updateManualSpecialAward(_ category: SpecialAwardCategory, value: String?) async {
        guard savingSpecialAward == nil else { return }
        savingSpecialAward = category
        defer { savingSpecialAward = nil }

        let cleanValue = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        do {
            try await store.setManualSpecialAward(category, value: cleanValue)
            specialAwardDrafts[category] = cleanValue
            if cleanValue.isEmpty {
                store.showOperationSuccess("Premio actualizado", message: "\(category.title) quedó sin asignar.")
            } else {
                store.showOperationSuccess("Premio guardado", message: "\(category.title): \(cleanValue).")
            }
        } catch {
            store.showOperationFailure("No se pudo guardar premio", message: error.localizedDescription)
        }
    }

    private func specialAwardDraftBinding(for category: SpecialAwardCategory) -> Binding<String> {
        Binding(
            get: { specialAwardDraftValue(for: category) },
            set: { specialAwardDrafts[category] = $0 }
        )
    }

    private func specialAwardDraftValue(for category: SpecialAwardCategory) -> String {
        specialAwardDrafts[category] ?? store.specialAwardManualValue(for: category) ?? ""
    }

    private func syncSpecialAwardDrafts() {
        specialAwardDrafts = Dictionary(
            uniqueKeysWithValues: SpecialAwardCategory.manualEntryCases.map { category in
                (category, store.specialAwardManualValue(for: category) ?? "")
            }
        )
    }
}

private struct FavoriteManualSpecialAwardField: View {
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
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: category.systemImage)
                    .font(.headline.weight(.black))
                    .foregroundStyle(LevitTheme.pink)
                    .frame(width: 42, height: 42)
                    .background(LevitTheme.palePink, in: RoundedRectangle(cornerRadius: 12, style: .continuous))

                VStack(alignment: .leading, spacing: 3) {
                    Text(category.title)
                        .font(.headline.weight(.black))
                        .foregroundStyle(LevitTheme.ink)
                    Text(hasSavedValue ? "Guardada manualmente" : "Escritura manual")
                        .font(.caption.weight(.black))
                        .foregroundStyle(hasSavedValue ? LevitTheme.pink : LevitTheme.muted)
                }

                Spacer()
            }

            HStack(spacing: 10) {
                TextField("Escribir nombre", text: $value)
                    .textInputAutocapitalization(.words)
                    .disableAutocorrection(true)
                    .font(.headline.weight(.black))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 14)
                    .background(LevitTheme.softFill, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(LevitTheme.line))

                Button(action: onSave) {
                    if isSaving {
                        ProgressView()
                            .controlSize(.small)
                            .tint(.white)
                    } else {
                        Image(systemName: "checkmark")
                            .font(.headline.weight(.black))
                    }
                }
                .frame(width: 56, height: 56)
                .foregroundStyle(.white)
                .background(LevitTheme.pinkGradient, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .disabled(!canSave)
                .opacity(canSave ? 1 : 0.48)
                .buttonStyle(.plain)

                Button(action: onClear) {
                    Image(systemName: "xmark")
                        .font(.headline.weight(.black))
                }
                .frame(width: 56, height: 56)
                .foregroundStyle(LevitTheme.muted)
                .background(LevitTheme.solidSurface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(LevitTheme.line))
                .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .disabled(isSaving || (!hasSavedValue && value.isEmpty))
                .opacity(isSaving || (!hasSavedValue && value.isEmpty) ? 0.48 : 1)
                .buttonStyle(.plain)
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, minHeight: 166, alignment: .topLeading)
        .background(LevitTheme.solidSurface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(LevitTheme.line))
    }
}

private struct FavoriteMetricCard: View {
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
                    .font(.title2.monospacedDigit().weight(.black))
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

private struct FavoriteRankingBlockSection: View {
    let block: FavoriteRankingBlock

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                Image(systemName: "square.stack.3d.up.fill")
                    .font(.headline.weight(.bold))
                    .foregroundStyle(LevitTheme.pink)
                    .frame(width: 38, height: 38)
                    .background(LevitTheme.palePink, in: Circle())

                VStack(alignment: .leading, spacing: 2) {
                    Text(block.blockName)
                        .font(.title3.weight(.black))
                    Text("\(block.totalVotes) voto\(block.totalVotes == 1 ? "" : "s")")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(LevitTheme.muted)
                }

                Spacer()
            }

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 300), spacing: 12, alignment: .top)], alignment: .leading, spacing: 12) {
                ForEach(block.categories) { category in
                    FavoriteRankingCategoryCard(ranking: category)
                }
            }
        }
        .padding(20)
        .background(LevitTheme.surface, in: RoundedRectangle(cornerRadius: 22))
        .overlay(RoundedRectangle(cornerRadius: 22).stroke(LevitTheme.cardStroke))
        .shadow(color: .black.opacity(0.045), radius: 22, x: 0, y: 12)
    }
}

private struct FavoriteRankingCategoryCard: View {
    let ranking: FavoriteCategoryRanking

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: ranking.category.systemImage)
                    .font(.headline.weight(.bold))
                    .foregroundStyle(LevitTheme.pink)
                    .frame(width: 32, height: 32)
                    .background(LevitTheme.palePink, in: Circle())
                Text(ranking.category.title)
                    .font(.headline.weight(.black))
                    .lineLimit(1)
                Spacer()
                Text("\(ranking.totalVotes) voto\(ranking.totalVotes == 1 ? "" : "s")")
                    .font(.caption.weight(.black))
                    .foregroundStyle(LevitTheme.muted)
            }

            if ranking.items.isEmpty {
                Text("Sin votos")
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(LevitTheme.muted)
                    .frame(maxWidth: .infinity, minHeight: 110, alignment: .center)
                    .background(LevitTheme.softFill, in: RoundedRectangle(cornerRadius: 14))
            } else {
                VStack(spacing: 8) {
                    ForEach(ranking.items) { item in
                        FavoriteRankingRow(item: item)
                    }
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, minHeight: 220, alignment: .topLeading)
        .background(LevitTheme.solidSurface, in: RoundedRectangle(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(LevitTheme.line))
    }
}

private struct FavoriteRankingRow: View {
    let item: FavoriteRankingItem

    private var judgesText: String {
        let names = item.judges.joined(separator: ", ")
        return item.votes == 1 ? "Votó: \(names)" : "Votaron: \(names)"
    }

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 5) {
                Text(item.routine.name)
                    .font(.headline.weight(.black))
                    .foregroundStyle(LevitTheme.ink)
                    .lineLimit(2)
                    .minimumScaleFactor(0.74)
                Text("#\(item.routine.id)")
                    .font(.caption.monospacedDigit().weight(.black))
                    .foregroundStyle(LevitTheme.muted)
                    .lineLimit(1)
                Text(judgesText)
                    .font(.caption2.weight(.black))
                    .foregroundStyle(LevitTheme.pink)
                    .lineLimit(2)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                Text("\(item.votes)")
                    .font(.title3.monospacedDigit().weight(.black))
                    .foregroundStyle(LevitTheme.ink)
                Text("voto\(item.votes == 1 ? "" : "s")")
                    .font(.caption2.weight(.black))
                    .foregroundStyle(LevitTheme.muted)
            }
            .frame(width: 48, alignment: .trailing)
        }
        .padding(12)
        .background(item.rank == 1 ? LevitTheme.palePink.opacity(0.72) : LevitTheme.softFill, in: RoundedRectangle(cornerRadius: 14))
    }
}
