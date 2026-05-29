import SwiftUI
import UIKit

struct LimitedScoreTextField: UIViewRepresentable {
    @Binding var text: String
    let maxScore: Double
    let criterionID: Int
    var focusedCriterionID: FocusState<Int?>.Binding
    let fontSize: CGFloat

    func makeUIView(context: Context) -> UITextField {
        let textField = UITextField()
        textField.delegate = context.coordinator
        textField.keyboardType = .decimalPad
        textField.textAlignment = .center
        textField.adjustsFontSizeToFitWidth = true
        textField.minimumFontSize = max(14, fontSize * 0.58)
        textField.backgroundColor = .clear
        textField.addTarget(context.coordinator, action: #selector(Coordinator.editingChanged(_:)), for: .editingChanged)
        return textField
    }

    func updateUIView(_ textField: UITextField, context: Context) {
        context.coordinator.parent = self
        let sanitized = Self.sanitized(text, maxScore: maxScore)
        if sanitized != text {
            DispatchQueue.main.async {
                self.text = sanitized
            }
        }
        if textField.text != sanitized {
            textField.text = sanitized
        }
        textField.font = UIFont.monospacedDigitSystemFont(ofSize: fontSize, weight: .black)
        textField.textColor = Self.inkColor
        if focusedCriterionID.wrappedValue == criterionID, !textField.isFirstResponder {
            textField.becomeFirstResponder()
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    final class Coordinator: NSObject, UITextFieldDelegate {
        var parent: LimitedScoreTextField

        init(parent: LimitedScoreTextField) {
            self.parent = parent
        }

        @objc func editingChanged(_ textField: UITextField) {
            parent.text = LimitedScoreTextField.sanitized(textField.text ?? "", maxScore: parent.maxScore)
        }

        func textFieldDidBeginEditing(_ textField: UITextField) {
            parent.focusedCriterionID.wrappedValue = parent.criterionID
        }

        func textFieldDidEndEditing(_ textField: UITextField) {
            let finalized = LimitedScoreTextField.finalized(textField.text ?? "", maxScore: parent.maxScore)
            textField.text = finalized
            parent.text = finalized
            if parent.focusedCriterionID.wrappedValue == parent.criterionID {
                parent.focusedCriterionID.wrappedValue = nil
            }
        }

        func textField(_ textField: UITextField, shouldChangeCharactersIn range: NSRange, replacementString string: String) -> Bool {
            let current = textField.text ?? ""
            guard let textRange = Range(range, in: current) else { return false }
            let candidate = current.replacingCharacters(in: textRange, with: string)
            guard let normalized = LimitedScoreTextField.normalizedCandidate(candidate) else { return false }

            if let value = Double(normalized), value > parent.maxScore {
                let maxText = LimitedScoreTextField.scoreText(parent.maxScore)
                textField.text = maxText
                parent.text = maxText
                return false
            }

            parent.text = candidate
            return true
        }
    }

    private static var inkColor: UIColor {
        UIColor { traitCollection in
            if traitCollection.userInterfaceStyle == .dark {
                return UIColor(red: 0.94, green: 0.95, blue: 0.98, alpha: 1.0)
            }
            return UIColor(red: 0.12, green: 0.13, blue: 0.17, alpha: 1.0)
        }
    }

    private static func normalizedCandidate(_ text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalized = trimmed.replacingOccurrences(of: ",", with: ".")
        guard normalized.allSatisfy({ $0.isNumber || $0 == "." }) else { return nil }
        guard normalized.filter({ $0 == "." }).count <= 1 else { return nil }
        return normalized
    }

    private static func sanitized(_ text: String, maxScore: Double) -> String {
        guard let normalized = normalizedCandidate(text) else { return "" }
        guard normalized != "." else { return "" }
        guard let value = Double(normalized) else { return text }
        return value > maxScore ? scoreText(maxScore) : text
    }

    private static func finalized(_ text: String, maxScore: Double) -> String {
        guard let normalized = normalizedCandidate(text),
              let value = Double(normalized)
        else {
            return ""
        }
        return scoreText(min(max(value, 0), maxScore))
    }

    private static func scoreText(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(0...1)))
    }
}

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
            ContentUnavailableView("Sin coreografías", systemImage: "tray")
                .foregroundStyle(LevitTheme.ink)
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
                    Text("Selecciona quién va a calificar antes de entrar a la hoja de jueceo.")
                        .font(.title3.weight(.medium))
                        .foregroundStyle(LevitTheme.muted)
                }

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 190, maximum: 230), spacing: 18)], spacing: 18) {
                    ForEach(store.orderedJudges, id: \.self) { judge in
                        Button {
                            store.selectJudge(judge)
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
        .foregroundStyle(LevitTheme.ink)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(LevitTheme.paper.ignoresSafeArea())
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
    @State private var customPenalty = ""
    @State private var didSubmit = false
    @State private var errorMessage: String?
    @FocusState private var focusedCriterionID: Int?

    private var routineIndex: Int {
        (routines.firstIndex { $0.id == routine.id } ?? 0) + 1
    }

    private var subtotal: Double {
        max(0, scoreSubtotal + penaltyValue)
    }

    private var scoreSubtotal: Double {
        template.criteria.reduce(0) { sum, criterion in
            sum + scoreValue(for: criterion)
        }
    }

    private var penaltyValue: Double {
        if store.isAdmin, penalty == "Otro" {
            return min(max(Double(customPenalty.replacingOccurrences(of: ",", with: ".")) ?? 0, -100), 0)
        }
        return Double(penalty) ?? 0
    }

    private var maxTotal: Double {
        template.maxScore > 0 ? template.maxScore : template.criteria.reduce(0) { $0 + $1.maxScore }
    }

    private var nextRoutine: Routine? {
        guard let index = routines.firstIndex(where: { $0.id == routine.id }) else { return nil }
        let next = routines.index(after: index)
        return routines.indices.contains(next) ? routines[next] : nil
    }

    private var scoringJudge: String {
        store.scoringJudge
    }

    private var penaltyOptions: [String] {
        store.isAdmin ? ["0", "-1", "-2", "Otro"] : ["0", "-1", "-2"]
    }

    var body: some View {
        VStack(spacing: 0) {
            topHeader
            Divider().overlay(LevitTheme.line)

            HStack(alignment: .top, spacing: 28) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        ForEach(groupedCriteria, id: \.section) { group in
                            VStack(alignment: .leading, spacing: 10) {
                                Text(group.section.uppercased())
                                    .font(.caption.weight(.black))
                                    .foregroundStyle(LevitTheme.muted)
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

                ScrollView {
                    sidePanel
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                        .padding(.bottom, 22)
                }
                .frame(width: 330)
                .padding(.top, 22)
            }
            .padding(.horizontal, 34)
        }
        .foregroundStyle(LevitTheme.ink)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(LevitTheme.paper.ignoresSafeArea())
        .onAppear(perform: loadDraft)
        .onChange(of: routine.id) { _, _ in loadDraft() }
        .onChange(of: scoringJudge) { _, _ in loadDraft() }
    }

    private var topHeader: some View {
        HStack(alignment: .top, spacing: 22) {
            Button(action: onBack) {
                Label("Volver", systemImage: "chevron.left")
                    .font(.headline.weight(.bold))
                    .foregroundStyle(LevitTheme.muted)
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
                    .foregroundStyle(LevitTheme.muted)
                HStack(spacing: 6) {
                    LevitTag(routine.division)
                    LevitTag(routine.category)
                    LevitTag(routine.genre)
                }
            }
            .frame(maxWidth: 520)

            Spacer()

            VStack(alignment: .leading, spacing: 8) {
                Text("\(routineIndex) / \(max(routines.count, 1))")
                    .font(.title2.monospacedDigit().weight(.black))
                Text("Calificadas")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(LevitTheme.muted)
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
            if store.isAdminEditingAsJudge {
                Label("Editando como \(scoringJudge)", systemImage: "person.fill.viewfinder")
                    .font(.callout.weight(.black))
                    .foregroundStyle(LevitTheme.pink)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(LevitTheme.palePink, in: RoundedRectangle(cornerRadius: 15))
            }

            VStack(alignment: .leading, spacing: 22) {
                Text("PUNTAJE TOTAL")
                    .font(.caption.weight(.black))
                    .foregroundStyle(LevitTheme.muted)
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(subtotal.formatted(.number.precision(.fractionLength(0...1))))
                        .font(.system(size: 72, weight: .black, design: .rounded))
                        .foregroundStyle(LevitTheme.hotPink)
                    Text("/ \(maxTotal.formatted(.number.precision(.fractionLength(0...1))))")
                        .font(.title.weight(.black))
                        .foregroundStyle(LevitTheme.muted)
                }
                if penaltyValue != 0 {
                    Text("Subtotal \(scoreSubtotal.formatted(.number.precision(.fractionLength(0...1)))) · Penalización \(penaltyValue.formatted(.number.precision(.fractionLength(0...1))))")
                        .font(.caption.weight(.black))
                        .foregroundStyle(LevitTheme.muted)
                }

                Label(didSubmit ? "Sincronizado" : store.syncStatus.title, systemImage: didSubmit ? "checkmark.circle.fill" : store.syncStatus.systemImage)
                    .font(.callout.weight(.bold))
                    .foregroundStyle(didSubmit ? Color.green : LevitTheme.muted)
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(LevitTheme.elevatedSurface, in: RoundedRectangle(cornerRadius: 20))
            .overlay(RoundedRectangle(cornerRadius: 20).stroke(LevitTheme.line))

            favoriteButtons

            Button {
                saveScores(advance: true)
            } label: {
                HStack {
                    Text("Guardar y continuar")
                    Spacer()
                    Image(systemName: "arrow.right")
                }
                .font(.headline.weight(.black))
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
                .foregroundStyle(LevitTheme.ink)
                .background(.clear, in: RoundedRectangle(cornerRadius: 16))
                .overlay(RoundedRectangle(cornerRadius: 16).stroke(LevitTheme.pink.opacity(0.75), lineWidth: 1.4))
            }
            .buttonStyle(.plain)

            if store.isAdminEditingAsJudge {
                Button {
                    exportCurrentRoutineToDrive()
                } label: {
                    HStack {
                        if store.driveExportStatus.isExporting {
                            ProgressView()
                                .tint(LevitTheme.pink)
                        } else {
                            Image(systemName: "icloud.and.arrow.up")
                        }
                        Text("Exportar a Drive")
                            .lineLimit(1)
                            .minimumScaleFactor(0.72)
                        Spacer()
                    }
                    .font(.headline.weight(.black))
                    .padding(.horizontal, 20)
                    .padding(.vertical, 15)
                    .foregroundStyle(store.driveExportStatus.isExporting ? LevitTheme.muted : LevitTheme.pink)
                    .background(LevitTheme.solidSurface, in: RoundedRectangle(cornerRadius: 16))
                    .overlay(RoundedRectangle(cornerRadius: 16).stroke(LevitTheme.pink.opacity(0.45), lineWidth: 1.2))
                }
                .buttonStyle(.plain)
                .disabled(store.driveExportStatus.isExporting)
                .opacity(store.driveExportStatus.isExporting ? 0.72 : 1)

                if let message = store.driveExportMessage {
                    Label(message, systemImage: store.driveExportStatus.systemImage)
                        .font(.caption.weight(.bold))
                        .foregroundStyle(driveStatusColor)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            if !routines.isEmpty {
                Divider().overlay(LevitTheme.line)

                routinePicker
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

    private var favoriteButtons: some View {
        VStack(spacing: 10) {
            ForEach(FavoriteCategory.allCases) { category in
                favoriteButton(category)
            }
        }
    }

    private func favoriteButton(_ category: FavoriteCategory) -> some View {
        let isSelected = store.isFavorite(routine, category: category, judge: scoringJudge)
        return Button {
            store.toggleFavorite(category, routine: routine, judge: scoringJudge)
        } label: {
            HStack(spacing: 12) {
                Image(systemName: category.systemImage)
                    .font(.headline.weight(.bold))
                    .frame(width: 28)

                Text(category.title)
                    .font(.callout.weight(.black))
                    .lineLimit(1)
                    .minimumScaleFactor(0.78)

                Spacer()

                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.headline.weight(.bold))
                    .foregroundStyle(isSelected ? LevitTheme.pink : LevitTheme.muted)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 13)
            .foregroundStyle(isSelected ? LevitTheme.pink : LevitTheme.ink)
            .background(isSelected ? LevitTheme.palePink : LevitTheme.solidSurface, in: RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(isSelected ? LevitTheme.pink.opacity(0.45) : LevitTheme.line, lineWidth: isSelected ? 1.4 : 1))
        }
        .buttonStyle(.plain)
    }

    private var routinePicker: some View {
        HStack(spacing: 14) {
            Image(systemName: "figure.dance")
                .font(.title3.weight(.bold))
                .foregroundStyle(LevitTheme.pink)
                .frame(width: 48, height: 48)
                .background(LevitTheme.pink.opacity(0.12), in: RoundedRectangle(cornerRadius: 14))

            VStack(alignment: .leading, spacing: 6) {
                Text("Coreografía del bloque")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(LevitTheme.muted)

                Picker(
                    "",
                    selection: Binding(
                        get: { selectedRoutineIDForPicker },
                        set: { store.selectedRoutineID = $0 }
                    )
                ) {
                    ForEach(routines) { routine in
                        Text("#\(routine.id) \(routine.name)")
                            .tag(routine.id)
                    }
                }
                .buttonStyle(.plain)
                .pickerStyle(.menu)
                .tint(LevitTheme.ink)
                .labelsHidden()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(18)
        .background(LevitTheme.elevatedSurface, in: RoundedRectangle(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(LevitTheme.line))
    }

    private var selectedRoutineIDForPicker: String {
        routines.contains { $0.id == store.selectedRoutineID } ? store.selectedRoutineID : routine.id
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

    private var penaltyControl: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("PENALIZACIÓN")
                .font(.caption.weight(.black))
                .foregroundStyle(LevitTheme.muted)
            HStack(spacing: 10) {
                ForEach(penaltyOptions, id: \.self) { item in
                    Button {
                        penalty = item
                        if item != "Otro" {
                            customPenalty = ""
                        }
                        didSubmit = false
                    } label: {
                        Text(item)
                            .font(.callout.weight(.black))
                            .frame(width: item == "Otro" ? 116 : 92, height: 42)
                            .foregroundStyle(penalty == item ? LevitTheme.pink : LevitTheme.ink)
                            .background(penalty == item ? LevitTheme.palePink : LevitTheme.softFill, in: RoundedRectangle(cornerRadius: 10))
                            .overlay(RoundedRectangle(cornerRadius: 10).stroke(penalty == item ? LevitTheme.pink : LevitTheme.line))
                    }
                    .buttonStyle(.plain)
                }
            }
            if store.isAdmin, penalty == "Otro" {
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
                .foregroundStyle(LevitTheme.ink)
                .padding(.horizontal, 14)
                .frame(width: 150, height: 44)
                .background(LevitTheme.solidSurface, in: RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(LevitTheme.line))
            }
        }
    }

    private var feedbackEditor: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("RETROALIMENTACIÓN")
                    .font(.caption.weight(.black))
                    .foregroundStyle(LevitTheme.muted)
                Spacer()
                Text("\(store.feedbackBody(for: routine, judge: scoringJudge).count) / 300")
                    .font(.caption.monospacedDigit().weight(.bold))
                    .foregroundStyle(LevitTheme.muted)
            }

            ZStack(alignment: .topLeading) {
                TextEditor(text: Binding(
                    get: { store.feedbackBody(for: routine, judge: scoringJudge) },
                    set: { store.setFeedback(String($0.prefix(300)), routine: routine, judge: scoringJudge) }
                ))
                .frame(minHeight: 96)
                .padding(8)
                .scrollContentBackground(.hidden)
                .foregroundStyle(LevitTheme.ink)
                .background(LevitTheme.solidSurface, in: RoundedRectangle(cornerRadius: 13))
                .overlay(RoundedRectangle(cornerRadius: 13).stroke(LevitTheme.line))

                if store.feedbackBody(for: routine, judge: scoringJudge).isEmpty {
                    Text("Excelente ejecución técnica y limpieza en las transiciones.")
                        .font(.callout.weight(.medium))
                        .foregroundStyle(LevitTheme.muted.opacity(0.75))
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
            let saved = store.score(for: routine, judge: scoringJudge, criterion: criterion)
            return (criterion.id, saved.formatted(.number.precision(.fractionLength(0...1))))
        })
        loadPenalty(store.penalty(for: routine, judge: scoringJudge))
        didSubmit = false
        errorMessage = nil
        focusedCriterionID = nil
    }

    @discardableResult
    private func saveScores(advance: Bool) -> Bool {
        guard validateScoresBeforeSaving() else { return false }

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
        return true
    }

    private func exportCurrentRoutineToDrive() {
        guard !store.driveExportStatus.isExporting else { return }
        guard saveScores(advance: false) else { return }
        Task {
            await store.exportRoutineToDrive(routine: routine, judge: scoringJudge)
        }
    }

    private func validateScoresBeforeSaving() -> Bool {
        guard let missingOrInvalid = template.criteria.first(where: { !isValidScoreText(draftScores[$0.id] ?? "", maxScore: $0.maxScore) }) else {
            return true
        }

        didSubmit = false
        errorMessage = "Completa todas las notas entre 1 y \(missingOrInvalid.maxScore.formatted(.number.precision(.fractionLength(0...1))))."
        focusedCriterionID = missingOrInvalid.id
        return false
    }

    private func isValidScoreText(_ text: String, maxScore: Double) -> Bool {
        let cleanText = text.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: ",", with: ".")
        guard !cleanText.isEmpty, let value = Double(cleanText) else { return false }
        return value >= 1 && value <= maxScore
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
            penalty = store.isAdmin ? "Otro" : "0"
            customPenalty = store.isAdmin ? value.formatted(.number.precision(.fractionLength(0...1))) : ""
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
                    .foregroundStyle(LevitTheme.ink)
                    .lineLimit(1)
                Text("1 a \(criterion.maxScore.formatted(.number.precision(.fractionLength(0...1)))) puntos")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(LevitTheme.muted)
            }

            Spacer()

            Button(action: onDecrement) {
                Image(systemName: "minus")
                    .font(.headline.weight(.black))
                    .frame(width: 40, height: 40)
                    .foregroundStyle(LevitTheme.ink)
                    .background(LevitTheme.softFill, in: Circle())
            }
            .buttonStyle(.plain)

            LimitedScoreTextField(
                text: $value,
                maxScore: criterion.maxScore,
                criterionID: criterion.id,
                focusedCriterionID: focusedCriterionID,
                fontSize: 26
            )
                .frame(width: 54, height: 42)

            Button(action: onIncrement) {
                Image(systemName: "plus")
                    .font(.headline.weight(.black))
                    .frame(width: 40, height: 40)
                    .foregroundStyle(LevitTheme.ink)
                    .background(LevitTheme.softFill, in: Circle())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        .background(LevitTheme.elevatedSurface)
        .overlay(alignment: .bottom) {
            Rectangle().fill(LevitTheme.line).frame(height: 1)
        }
    }
}
