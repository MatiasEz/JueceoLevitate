import Foundation
import UIKit

enum PDFExporter {
    static func export(
        results: [RoutineResult],
        judges: [String],
        sourceName: String,
        title: String = "Calificaciones y dictamen final",
        templateForRoutine: (Routine) -> JudgingTemplate,
        scoreForCriterion: (Routine, String, Criterion) -> Double,
        penaltyForRoutine: (Routine, String) -> Double
    ) -> URL? {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(filename(for: title))
            .appendingPathExtension("pdf")

        let format = UIGraphicsPDFRendererFormat()
        format.documentInfo = [
            kCGPDFContextCreator as String: "Jueceo Coreografías",
            kCGPDFContextTitle as String: title
        ]

        let page = CGRect(x: 0, y: 0, width: 842, height: 595)
        let margin: CGFloat = 24
        let renderer = UIGraphicsPDFRenderer(bounds: page, format: format)
        let groups = groupedResults(results)

        do {
            try renderer.writePDF(to: url) { context in
                var didStartPage = false

                for group in groups {
                    let template = templateForRoutine(group.results.first?.routine ?? results.first?.routine ?? placeholderRoutine)
                    let criteria = template.criteria.sorted { $0.id < $1.id }
                    var y = margin

                    context.beginPage()
                    didStartPage = true
                    y = drawPageHeader(title: title, sourceName: sourceName, groupTitle: group.title, y: y, margin: margin, page: page)
                    y = drawTableHeader(criteria: criteria, y: y, margin: margin, page: page)

                    for (routineIndex, result) in group.results.enumerated() {
                        let rowCount = max(judges.count, 1)
                        let neededHeight = CGFloat(rowCount) * Layout.rowHeight
                        if y + neededHeight > page.height - margin {
                            context.beginPage()
                            y = margin
                            y = drawPageHeader(title: title, sourceName: sourceName, groupTitle: "\(group.title) - continuacion", y: y, margin: margin, page: page)
                            y = drawTableHeader(criteria: criteria, y: y, margin: margin, page: page)
                        }

                        let fill = routineIndex.isMultiple(of: 2) ? Theme.paleYellow : .white
                        drawRoutineRows(
                            result: result,
                            position: routineIndex + 1,
                            y: y,
                            judges: judges,
                            criteria: criteria,
                            fill: fill,
                            page: page,
                            margin: margin,
                            scoreForCriterion: scoreForCriterion,
                            penaltyForRoutine: penaltyForRoutine
                        )
                        y += neededHeight
                    }
                }

                if !didStartPage {
                    context.beginPage()
                    _ = drawPageHeader(title: title, sourceName: sourceName, groupTitle: "Sin resultados", y: margin, margin: margin, page: page)
                }
            }
            return url
        } catch {
            return nil
        }
    }

    private static func groupedResults(_ results: [RoutineResult]) -> [(title: String, results: [RoutineResult])] {
        let grouped = Dictionary(grouping: results) { result in
            clean(result.routine.genre, fallback: "SIN GÉNERO")
        }

        return grouped
            .map { title, items in
                (
                    title,
                    items.sorted {
                        if $0.total == $1.total {
                            return (Int($0.routine.id) ?? Int.max) < (Int($1.routine.id) ?? Int.max)
                        }
                        return $0.total > $1.total
                    }
                )
            }
            .sorted { lhs, rhs in lhs.title.localizedStandardCompare(rhs.title) == .orderedAscending }
    }

    private static func drawPageHeader(title: String, sourceName: String, groupTitle: String, y: CGFloat, margin: CGFloat, page: CGRect) -> CGFloat {
        let fullWidth = page.width - margin * 2
        let headerTitle = clean(sourceName, fallback: "")
        let displayedTitle = headerTitle.isEmpty ? groupTitle : "\(headerTitle) - \(groupTitle)"
        drawCell(
            rect: CGRect(x: margin, y: y, width: fullWidth, height: 30),
            text: displayedTitle.uppercased(),
            fill: .white,
            fontSize: 22,
            weight: .bold
        )

        let metaY = y + 32
        drawText(title, in: CGRect(x: margin, y: metaY, width: fullWidth * 0.58, height: 16), size: 9.5, color: .darkGray)
        drawText(sourceName, in: CGRect(x: page.midX, y: metaY, width: page.midX - margin, height: 16), size: 9.5, color: .darkGray, alignment: .right)
        return metaY + 24
    }

    private static func drawTableHeader(criteria: [Criterion], y: CGFloat, margin: CGFloat, page: CGRect) -> CGFloat {
        let metrics = Layout.metrics(criteriaCount: criteria.count, pageWidth: page.width, margin: margin)
        var x = margin

        drawCell(rect: CGRect(x: x, y: y, width: metrics.numberWidth, height: Layout.headerHeight), text: "#", fill: Theme.headerFill, fontSize: 8, weight: .bold)
        x += metrics.numberWidth
        drawCell(rect: CGRect(x: x, y: y, width: metrics.routineWidth, height: Layout.headerHeight), text: "COREOGRAFÍA", fill: Theme.headerFill, fontSize: 8, weight: .bold)
        x += metrics.routineWidth
        drawCell(rect: CGRect(x: x, y: y, width: metrics.judgeWidth, height: Layout.headerHeight), text: "JUEZ", fill: Theme.headerFill, fontSize: 8, weight: .bold)
        x += metrics.judgeWidth

        let sections = sectionSpans(for: criteria)
        for span in sections {
            let sectionX = x + CGFloat(span.start) * metrics.criterionWidth
            let sectionWidth = CGFloat(span.count) * metrics.criterionWidth
            drawCell(
                rect: CGRect(x: sectionX, y: y, width: sectionWidth, height: Layout.sectionHeight),
                text: span.title.uppercased(),
                fill: .white,
                fontSize: 8.2,
                weight: .bold
            )
        }

        let idY = y + Layout.sectionHeight
        let labelY = idY + Layout.idHeight
        let maxY = labelY + Layout.labelHeight
        for (index, criterion) in criteria.enumerated() {
            let criterionX = x + CGFloat(index) * metrics.criterionWidth
            drawCell(
                rect: CGRect(x: criterionX, y: idY, width: metrics.criterionWidth, height: Layout.idHeight),
                text: "\(criterion.id)",
                fill: Theme.headerFill,
                fontSize: 7.5,
                weight: .bold
            )
            drawCell(
                rect: CGRect(x: criterionX, y: labelY, width: metrics.criterionWidth, height: Layout.labelHeight),
                text: criterion.label,
                fill: .white,
                fontSize: 5.2,
                weight: .regular,
                alignment: .center,
                padding: 2
            )
            drawCell(
                rect: CGRect(x: criterionX, y: maxY, width: metrics.criterionWidth, height: Layout.maxHeight),
                text: criterion.maxScore.formatted(.number.precision(.fractionLength(0...1))),
                fill: Theme.headerFill,
                fontSize: 7,
                weight: .bold
            )
        }

        x += CGFloat(criteria.count) * metrics.criterionWidth
        drawCell(rect: CGRect(x: x, y: y, width: metrics.totalWidth, height: Layout.headerHeight), text: "TOTAL", fill: Theme.headerFill, fontSize: 7.4, weight: .bold)
        x += metrics.totalWidth
        drawCell(rect: CGRect(x: x, y: y, width: metrics.averageWidth, height: Layout.headerHeight), text: "PROM.", fill: Theme.headerFill, fontSize: 7.4, weight: .bold)
        x += metrics.averageWidth
        drawCell(rect: CGRect(x: x, y: y, width: metrics.placeWidth, height: Layout.headerHeight), text: "LUGAR", fill: Theme.headerFill, fontSize: 7.4, weight: .bold)

        return y + Layout.headerHeight
    }

    private static func drawRoutineRows(
        result: RoutineResult,
        position: Int,
        y: CGFloat,
        judges: [String],
        criteria: [Criterion],
        fill: UIColor,
        page: CGRect,
        margin: CGFloat,
        scoreForCriterion: (Routine, String, Criterion) -> Double,
        penaltyForRoutine: (Routine, String) -> Double
    ) {
        let metrics = Layout.metrics(criteriaCount: criteria.count, pageWidth: page.width, margin: margin)
        let rowJudges = judges.isEmpty ? ["-"] : judges

        for (judgeIndex, judge) in rowJudges.enumerated() {
            let rowY = y + CGFloat(judgeIndex) * Layout.rowHeight
            var x = margin
            let isFirstJudge = judgeIndex == 0
            let subtotal = criteria.reduce(0) { sum, criterion in
                sum + scoreForCriterion(result.routine, judge, criterion)
            }
            let judgeTotal = subtotal > 0 ? max(0, subtotal + penaltyForRoutine(result.routine, judge)) : 0

            drawCell(
                rect: CGRect(x: x, y: rowY, width: metrics.numberWidth, height: Layout.rowHeight),
                text: isFirstJudge ? result.routine.id : "",
                fill: fill,
                fontSize: 7.6,
                weight: isFirstJudge ? .bold : .regular
            )
            x += metrics.numberWidth

            drawCell(
                rect: CGRect(x: x, y: rowY, width: metrics.routineWidth, height: Layout.rowHeight),
                text: isFirstJudge ? titleCase(result.routine.name) : "",
                fill: fill,
                fontSize: 7,
                weight: isFirstJudge ? .semibold : .regular,
                alignment: .left
            )
            x += metrics.routineWidth

            drawCell(
                rect: CGRect(x: x, y: rowY, width: metrics.judgeWidth, height: Layout.rowHeight),
                text: judge,
                fill: fill,
                fontSize: 7,
                weight: .semibold
            )
            x += metrics.judgeWidth

            for criterion in criteria {
                let score = scoreForCriterion(result.routine, judge, criterion)
                drawCell(
                    rect: CGRect(x: x, y: rowY, width: metrics.criterionWidth, height: Layout.rowHeight),
                    text: score > 0 ? score.formatted(.number.precision(.fractionLength(0...1))) : "",
                    fill: fill,
                    fontSize: 7.2
                )
                x += metrics.criterionWidth
            }

            drawCell(
                rect: CGRect(x: x, y: rowY, width: metrics.totalWidth, height: Layout.rowHeight),
                text: judgeTotal > 0 ? judgeTotal.formatted(.number.precision(.fractionLength(0...1))) : "",
                fill: fill,
                fontSize: 7.3,
                weight: .bold
            )
            x += metrics.totalWidth

            drawCell(
                rect: CGRect(x: x, y: rowY, width: metrics.averageWidth, height: Layout.rowHeight),
                text: isFirstJudge && result.total > 0 ? result.total.formatted(.number.precision(.fractionLength(1...2))) : "",
                fill: fill,
                fontSize: 7.3,
                weight: .bold
            )
            x += metrics.averageWidth

            drawCell(
                rect: CGRect(x: x, y: rowY, width: metrics.placeWidth, height: Layout.rowHeight),
                text: isFirstJudge && result.total > 0 ? "\(position)°" : "",
                fill: fill,
                fontSize: 7.3,
                weight: .bold
            )
        }
    }

    private static func sectionSpans(for criteria: [Criterion]) -> [(title: String, start: Int, count: Int)] {
        var spans: [(title: String, start: Int, count: Int)] = []
        for (index, criterion) in criteria.enumerated() {
            let section = clean(criterion.section, fallback: "CRITERIOS")
            if let last = spans.last, last.title == section {
                spans[spans.count - 1] = (last.title, last.start, last.count + 1)
            } else {
                spans.append((section, index, 1))
            }
        }
        return spans
    }

    private static func drawCell(
        rect: CGRect,
        text: String,
        fill: UIColor,
        fontSize: CGFloat,
        weight: UIFont.Weight = .regular,
        color: UIColor = .black,
        alignment: NSTextAlignment = .center,
        padding: CGFloat = 3
    ) {
        guard let context = UIGraphicsGetCurrentContext() else { return }
        context.setFillColor(fill.cgColor)
        context.fill(rect)
        context.setStrokeColor(Theme.grid.cgColor)
        context.setLineWidth(0.55)
        context.stroke(rect)

        let textRect = rect.insetBy(dx: padding, dy: 2)
        drawText(text, in: textRect, size: fontSize, weight: weight, color: color, alignment: alignment)
    }

    private static func drawText(
        _ text: String,
        in rect: CGRect,
        size: CGFloat,
        weight: UIFont.Weight = .regular,
        color: UIColor = .black,
        alignment: NSTextAlignment = .center
    ) {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = alignment
        paragraph.lineBreakMode = .byTruncatingTail
        paragraph.minimumLineHeight = size * 1.02
        paragraph.maximumLineHeight = size * 1.14
        let attributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: size, weight: weight),
            .foregroundColor: color,
            .paragraphStyle: paragraph
        ]
        text.draw(with: rect, options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine], attributes: attributes, context: nil)
    }

    private static func clean(_ value: String, fallback: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? fallback : trimmed
    }

    private static func titleCase(_ value: String) -> String {
        value.localizedLowercase.capitalized
    }

    private static func filename(for title: String) -> String {
        let allowed = title
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .lowercased()
            .map { character -> Character in
                character.isLetter || character.isNumber ? character : "-"
            }
        let compact = String(allowed)
            .split(separator: "-")
            .filter { !$0.isEmpty }
            .joined(separator: "-")
        return compact.isEmpty ? "dictamen-final" : compact
    }

    private static let placeholderRoutine = Routine(
        id: "",
        blockID: nil,
        block: "",
        name: "",
        academy: "",
        division: "",
        genre: "",
        level: "",
        category: "",
        choreographer: "",
        state: "",
        time: "",
        duration: ""
    )

    private enum Theme {
        static let paleYellow = UIColor(red: 0.996, green: 0.949, blue: 0.796, alpha: 1)
        static let headerFill = UIColor(red: 0.92, green: 0.92, blue: 0.92, alpha: 1)
        static let grid = UIColor(white: 0.12, alpha: 1)
    }

    private enum Layout {
        static let sectionHeight: CGFloat = 18
        static let idHeight: CGFloat = 15
        static let labelHeight: CGFloat = 48
        static let maxHeight: CGFloat = 15
        static let rowHeight: CGFloat = 18

        static var headerHeight: CGFloat {
            sectionHeight + idHeight + labelHeight + maxHeight
        }

        static func metrics(criteriaCount: Int, pageWidth: CGFloat, margin: CGFloat) -> Metrics {
            let safeCriteriaCount = max(criteriaCount, 1)
            let numberWidth: CGFloat = 34
            let judgeWidth: CGFloat = 54
            let totalWidth: CGFloat = 38
            let averageWidth: CGFloat = 42
            let placeWidth: CGFloat = 34
            let availableWidth = pageWidth - margin * 2
            let fixedWidth = numberWidth + judgeWidth + totalWidth + averageWidth + placeWidth
            let routineWidth = criteriaCount > 15 ? CGFloat(100) : CGFloat(126)
            let criterionWidth = max(24, (availableWidth - fixedWidth - routineWidth) / CGFloat(safeCriteriaCount))

            return Metrics(
                numberWidth: numberWidth,
                routineWidth: routineWidth,
                judgeWidth: judgeWidth,
                criterionWidth: criterionWidth,
                totalWidth: totalWidth,
                averageWidth: averageWidth,
                placeWidth: placeWidth
            )
        }

        struct Metrics {
            let numberWidth: CGFloat
            let routineWidth: CGFloat
            let judgeWidth: CGFloat
            let criterionWidth: CGFloat
            let totalWidth: CGFloat
            let averageWidth: CGFloat
            let placeWidth: CGFloat
        }
    }
}
