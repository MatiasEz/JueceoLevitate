import SwiftUI

struct JudgingView: View {
    @EnvironmentObject private var store: JudgingStore
    let routines: [Routine]
    @Binding var addingJudge: Bool
    let onBack: () -> Void
    @State private var isChoosingJudge = false

    var body: some View {
        if isChoosingJudge {
            JudgeSelectionView(addingJudge: $addingJudge) {
                isChoosingJudge = false
            }
        } else if let routine = store.selectedRoutine {
            ScoreSheet(
                routine: routine,
                template: store.template(for: routine),
                routines: routines,
                addingJudge: $addingJudge,
                isChoosingJudge: $isChoosingJudge,
                onBack: onBack
            )
        } else {
            ContentUnavailableView("Sin coreografias", systemImage: "tray")
                .foregroundStyle(.white)
        }
    }
}

private struct JudgeSelectionView: View {
    @EnvironmentObject private var store: JudgingStore
    @Binding var addingJudge: Bool
    let onContinue: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 26) {
                HStack {
                    LevitBrand()
                    Spacer()
                    Button {
                        addingJudge = true
                    } label: {
                        Label("Nuevo juez", systemImage: "person.badge.plus")
                            .font(.headline.weight(.bold))
                            .padding(.horizontal, 16)
                            .padding(.vertical, 12)
                            .foregroundStyle(.white)
                            .background(LevitTheme.pinkGradient, in: RoundedRectangle(cornerRadius: 14))
                    }
                    .buttonStyle(.plain)
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("Elegir juez")
                        .font(.system(size: 42, weight: .black, design: .rounded))
                        .foregroundStyle(LevitTheme.ink)
                    Text("Selecciona quien va a calificar antes de entrar a la hoja de jueceo.")
                        .font(.title3.weight(.medium))
                        .foregroundStyle(LevitTheme.muted)
                }

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 190, maximum: 230), spacing: 18)], spacing: 18) {
                    ForEach(store.judges, id: \.self) { judge in
                        Button {
                            store.selectedJudge = judge
                            onContinue()
                        } label: {
                            VStack(spacing: 16) {
                                Text(String(judge.prefix(2)))
                                    .font(.title.weight(.black))
                                    .frame(width: 74, height: 74)
                                    .foregroundStyle(judge == store.selectedJudge ? .white : LevitTheme.pink)
                                    .background(judge == store.selectedJudge ? LevitTheme.pinkGradient : LinearGradient(colors: [LevitTheme.palePink, LevitTheme.palePink], startPoint: .top, endPoint: .bottom), in: Circle())

                                Text(judge)
                                    .font(.title2.weight(.black))
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.72)
                            }
                            .foregroundStyle(LevitTheme.ink)
                            .frame(maxWidth: .infinity)
                            .aspectRatio(1, contentMode: .fit)
                            .padding(18)
                            .background(LevitTheme.solidSurface, in: RoundedRectangle(cornerRadius: 22))
                            .overlay(RoundedRectangle(cornerRadius: 22).stroke(judge == store.selectedJudge ? LevitTheme.pink.opacity(0.32) : LevitTheme.line, lineWidth: 1))
                            .shadow(color: .black.opacity(0.05), radius: 18, x: 0, y: 10)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(34)
            .frame(maxWidth: 1040, alignment: .leading)
        }
        .background(LevitTheme.paper)
    }
}

private struct ScoreSheet: View {
    @EnvironmentObject private var store: JudgingStore
    let routine: Routine
    let template: JudgingTemplate
    let routines: [Routine]
    @Binding var addingJudge: Bool
    @Binding var isChoosingJudge: Bool
    let onBack: () -> Void

    @State private var draftScores: [Int: String] = [:]
    @State private var penalty = "0"
    @State private var didSubmit = false
    @State private var errorMessage: String?
    @FocusState private var focusedCriterionID: Int?

    private var routineIndex: Int {
        (routines.firstIndex { $0.id == routine.id } ?? 0) + 1
    }

    private var subtotal: Double {
        template.criteria.reduce(0) { sum, criterion in
            sum + scoreValue(for: criterion)
        }
    }

    private var maxTotal: Double {
        template.maxScore > 0 ? template.maxScore : template.criteria.reduce(0) { $0 + $1.maxScore }
    }

    private var nextRoutine: Routine? {
        guard let index = routines.firstIndex(where: { $0.id == routine.id }) else { return nil }
        let next = routines.index(after: index)
        return routines.indices.contains(next) ? routines[next] : nil
    }

    var body: some View {
        VStack(spacing: 0) {
            topHeader
            Divider().overlay(.white.opacity(0.08))

            HStack(alignment: .top, spacing: 28) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        ForEach(groupedCriteria, id: \.section) { group in
                            VStack(alignment: .leading, spacing: 10) {
                                Text(group.section.uppercased())
                                    .font(.caption.weight(.black))
                                    .foregroundStyle(.white.opacity(0.48))
                                    .tracking(0.6)

                                VStack(spacing: 0) {
                                    ForEach(group.criteria) { criterion in
                                        DarkCriterionRow(
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
                                .clipShape(RoundedRectangle(cornerRadius: 14))
                            }
                        }

                        penaltyControl
                        feedbackEditor
                    }
                    .padding(.vertical, 22)
                }

                sidePanel
                    .frame(width: 330)
                    .padding(.top, 22)
            }
            .padding(.horizontal, 34)
        }
        .foregroundStyle(.white)
        .background(
            LinearGradient(
                colors: [LevitTheme.dark, Color(red: 0.035, green: 0.043, blue: 0.060)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .onAppear(perform: loadDraft)
        .onChange(of: routine.id) { _, _ in loadDraft() }
        .onChange(of: store.selectedJudge) { _, _ in loadDraft() }
    }

    private var topHeader: some View {
        HStack(alignment: .top, spacing: 22) {
            Button(action: onBack) {
                Label("Volver", systemImage: "chevron.left")
                    .font(.headline.weight(.bold))
                    .foregroundStyle(.white.opacity(0.74))
            }
            .buttonStyle(.plain)

            Spacer()

            VStack(spacing: 7) {
                Text("#\(routine.id)")
                    .font(.headline.weight(.black))
                    .foregroundStyle(LevitTheme.pink)
                Text(routine.name)
                    .font(.system(size: 32, weight: .black, design: .rounded))
                    .lineLimit(1)
                    .minimumScaleFactor(0.62)
                Text(routine.academy)
                    .font(.callout.weight(.bold))
                    .foregroundStyle(.white.opacity(0.48))
                HStack(spacing: 6) {
                    LevitTag(routine.division, dark: true)
                    LevitTag(routine.category, dark: true)
                    LevitTag(routine.genre, dark: true)
                }
            }
            .frame(maxWidth: 520)

            Spacer()

            VStack(alignment: .leading, spacing: 8) {
                Text("\(routineIndex) / \(max(routines.count, 1))")
                    .font(.title2.monospacedDigit().weight(.black))
                Text("Calificadas")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.white.opacity(0.58))
                ProgressView(value: Double(routineIndex), total: Double(max(routines.count, 1)))
                    .tint(LevitTheme.pink)
                    .frame(width: 190)
            }
        }
        .padding(.horizontal, 34)
        .padding(.top, 24)
        .padding(.bottom, 18)
    }

    private var sidePanel: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 22) {
                Text("PUNTAJE TOTAL")
                    .font(.caption.weight(.black))
                    .foregroundStyle(.white.opacity(0.52))
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(subtotal.formatted(.number.precision(.fractionLength(0...1))))
                        .font(.system(size: 72, weight: .black, design: .rounded))
                        .foregroundStyle(LevitTheme.hotPink)
                    Text("/ \(maxTotal.formatted(.number.precision(.fractionLength(0...1))))")
                        .font(.title.weight(.black))
                        .foregroundStyle(.white.opacity(0.45))
                }

                Label(didSubmit ? "Sincronizado" : store.syncStatus.title, systemImage: didSubmit ? "checkmark.circle.fill" : store.syncStatus.systemImage)
                    .font(.callout.weight(.bold))
                    .foregroundStyle(didSubmit ? .green : .white.opacity(0.65))
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(LevitTheme.darkPanel2.opacity(0.92), in: RoundedRectangle(cornerRadius: 20))

            Button {
                submitScores(advance: false)
            } label: {
                Label("Guardar", systemImage: "square.and.arrow.down")
                    .font(.headline.weight(.black))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 17)
                    .foregroundStyle(.white)
                    .background(LevitTheme.pinkGradient, in: RoundedRectangle(cornerRadius: 16))
            }
            .buttonStyle(.plain)

            Button {
                submitScores(advance: true)
            } label: {
                HStack {
                    Text("Guardar y siguiente")
                    Spacer()
                    Image(systemName: "arrow.right")
                }
                .font(.headline.weight(.black))
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
                .foregroundStyle(.white)
                .background(.clear, in: RoundedRectangle(cornerRadius: 16))
                .overlay(RoundedRectangle(cornerRadius: 16).stroke(LevitTheme.pink.opacity(0.75), lineWidth: 1.4))
            }
            .buttonStyle(.plain)

            if let nextRoutine {
                Divider().overlay(.white.opacity(0.08))
                Button {
                    store.selectedRoutineID = nextRoutine.id
                } label: {
                    HStack(spacing: 14) {
                        Image(systemName: "figure.dance")
                            .font(.title3.weight(.bold))
                            .foregroundStyle(LevitTheme.pink)
                            .frame(width: 48, height: 48)
                            .background(LevitTheme.pink.opacity(0.12), in: RoundedRectangle(cornerRadius: 14))

                        VStack(alignment: .leading, spacing: 4) {
                            Text("Siguiente:")
                                .font(.caption.weight(.bold))
                                .foregroundStyle(.white.opacity(0.42))
                            Text("#\(nextRoutine.id) \(nextRoutine.name)")
                                .font(.callout.weight(.black))
                                .foregroundStyle(.white)
                                .lineLimit(1)
                            Text(nextRoutine.academy)
                                .font(.caption.weight(.bold))
                                .foregroundStyle(.white.opacity(0.48))
                                .lineLimit(1)
                        }

                        Spacer()
                        Image(systemName: "chevron.right")
                            .foregroundStyle(.white.opacity(0.68))
                    }
                    .padding(18)
                    .background(LevitTheme.darkPanel2.opacity(0.82), in: RoundedRectangle(cornerRadius: 18))
                }
                .buttonStyle(.plain)
            }

            if let errorMessage {
                Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                    .font(.callout.weight(.bold))
                    .foregroundStyle(.red)
                    .padding(.top, 4)
            }

            Spacer(minLength: 0)
        }
    }

    private var penaltyControl: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("PENALIZACION")
                .font(.caption.weight(.black))
                .foregroundStyle(.white.opacity(0.48))
            HStack(spacing: 10) {
                ForEach(["0", "-1", "-2", "Otro"], id: \.self) { item in
                    Button {
                        penalty = item
                    } label: {
                        Text(item)
                            .font(.callout.weight(.black))
                            .frame(width: item == "Otro" ? 116 : 92, height: 42)
                            .foregroundStyle(penalty == item ? .white : .white.opacity(0.66))
                            .background(penalty == item ? LevitTheme.pink.opacity(0.22) : .white.opacity(0.06), in: RoundedRectangle(cornerRadius: 10))
                            .overlay(RoundedRectangle(cornerRadius: 10).stroke(penalty == item ? LevitTheme.pink : .clear))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var feedbackEditor: some View {
        let key = store.feedbackKey(routineID: routine.id, judge: store.selectedJudge)
        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("RETROALIMENTACION")
                    .font(.caption.weight(.black))
                    .foregroundStyle(.white.opacity(0.48))
                Spacer()
                Text("\((store.feedback[key] ?? "").count) / 300")
                    .font(.caption.monospacedDigit().weight(.bold))
                    .foregroundStyle(.white.opacity(0.44))
            }

            ZStack(alignment: .topLeading) {
                TextEditor(text: Binding(
                    get: { store.feedback[key] ?? "" },
                    set: { store.setFeedback(String($0.prefix(300)), routine: routine, judge: store.selectedJudge) }
                ))
                .frame(minHeight: 96)
                .padding(8)
                .scrollContentBackground(.hidden)
                .foregroundStyle(.white)
                .background(LevitTheme.darkPanel, in: RoundedRectangle(cornerRadius: 13))
                .overlay(RoundedRectangle(cornerRadius: 13).stroke(.white.opacity(0.08)))

                if (store.feedback[key] ?? "").isEmpty {
                    Text("Excelente ejecucion tecnica y limpieza en las transiciones.")
                        .font(.callout.weight(.medium))
                        .foregroundStyle(.white.opacity(0.35))
                        .padding(16)
                        .allowsHitTesting(false)
                }
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
            let saved = store.score(for: routine, judge: store.selectedJudge, criterion: criterion)
            return (criterion.id, saved > 0 ? saved.formatted(.number.precision(.fractionLength(0...1))) : "")
        })
        didSubmit = false
        errorMessage = nil
        focusedCriterionID = nil
    }

    private func submitScores(advance: Bool) {
        guard let missingOrInvalid = template.criteria.first(where: { !isValidScoreText(draftScores[$0.id] ?? "", maxScore: $0.maxScore) }) else {
            let values = template.criteria.map { criterion in
                let value = Double((draftScores[criterion.id] ?? "").replacingOccurrences(of: ",", with: ".")) ?? 0
                return (criterion: criterion, value: value)
            }
            store.submitScores(values, routine: routine, judge: store.selectedJudge)
            didSubmit = true
            errorMessage = nil
            focusedCriterionID = nil
            if advance, let nextRoutine {
                store.selectedRoutineID = nextRoutine.id
            }
            return
        }

        didSubmit = false
        errorMessage = "Completa todas las notas entre 0 y \(missingOrInvalid.maxScore.formatted(.number.precision(.fractionLength(0...1))))."
        focusedCriterionID = missingOrInvalid.id
    }

    private func isValidScoreText(_ text: String, maxScore: Double) -> Bool {
        let cleanText = text.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: ",", with: ".")
        guard !cleanText.isEmpty, let value = Double(cleanText) else { return false }
        return value >= 0 && value <= maxScore
    }

    private func scoreValue(for criterion: Criterion) -> Double {
        Double((draftScores[criterion.id] ?? "").replacingOccurrences(of: ",", with: ".")) ?? 0
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

private struct DarkCriterionRow: View {
    let criterion: Criterion
    @Binding var value: String
    let onDecrement: () -> Void
    let onIncrement: () -> Void
    var focusedCriterionID: FocusState<Int?>.Binding

    var body: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 5) {
                Text("\(criterion.id). \(criterion.label)")
                    .font(.callout.weight(.black))
                    .foregroundStyle(.white.opacity(0.92))
                    .lineLimit(1)
                Text("0 a \(criterion.maxScore.formatted(.number.precision(.fractionLength(0...1)))) puntos")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.white.opacity(0.42))
            }

            Spacer()

            Button(action: onDecrement) {
                Image(systemName: "minus")
                    .font(.headline.weight(.black))
                    .frame(width: 40, height: 40)
                    .foregroundStyle(.white.opacity(0.78))
                    .background(.white.opacity(0.10), in: Circle())
            }
            .buttonStyle(.plain)

            TextField("0", text: $value)
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.center)
                .font(.system(size: 26, weight: .black, design: .rounded).monospacedDigit())
                .foregroundStyle(.white)
                .frame(width: 54, height: 42)
                .focused(focusedCriterionID, equals: criterion.id)

            Button(action: onIncrement) {
                Image(systemName: "plus")
                    .font(.headline.weight(.black))
                    .frame(width: 40, height: 40)
                    .foregroundStyle(.white.opacity(0.78))
                    .background(.white.opacity(0.10), in: Circle())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        .background(LevitTheme.darkPanel2.opacity(0.68))
        .overlay(alignment: .bottom) {
            Rectangle().fill(.black.opacity(0.22)).frame(height: 1)
        }
    }
}
