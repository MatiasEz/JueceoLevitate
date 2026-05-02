import Foundation
import UIKit

enum PDFExporter {
    static func export(results: [RoutineResult], judges: [String], sourceName: String) -> URL? {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("calificaciones-dictamen-final")
            .appendingPathExtension("pdf")

        let format = UIGraphicsPDFRendererFormat()
        format.documentInfo = [
            kCGPDFContextCreator as String: "Jueceo Coreografias",
            kCGPDFContextTitle as String: "Calificaciones y Dictamen Final"
        ]

        let page = CGRect(x: 0, y: 0, width: 842, height: 595)
        let renderer = UIGraphicsPDFRenderer(bounds: page, format: format)

        do {
            try renderer.writePDF(to: url) { context in
                context.beginPage()
                var y: CGFloat = 42
                draw("Calificaciones y Dictamen Final", x: 36, y: y, size: 20, weight: .bold)
                y += 20
                draw("Fuente: \(sourceName)", x: 36, y: y, size: 10, color: .darkGray)
                y += 34

                drawHeader(y: y, judges: judges)
                y += 22

                for (index, result) in results.enumerated() {
                    if y > 548 {
                        context.beginPage()
                        y = 42
                        drawHeader(y: y, judges: judges)
                        y += 22
                    }
                    drawRow(result: result, position: index + 1, y: y, judges: judges)
                    y += 19
                }
            }
            return url
        } catch {
            return nil
        }
    }

    private static func drawHeader(y: CGFloat, judges: [String]) {
        ["Pos", "#", "Coreografia", "Academia", "Categoria", "Total"].enumerated().forEach { item in
            draw(item.element, x: [36, 68, 105, 285, 470, 745][item.offset], y: y, size: 9, weight: .bold)
        }
    }

    private static func drawRow(result: RoutineResult, position: Int, y: CGFloat, judges: [String]) {
        let category = "\(result.routine.genre) \(result.routine.division) \(result.routine.category)"
        let values = [
            "\(position)",
            result.routine.id,
            result.routine.name,
            result.routine.academy,
            category,
            result.total > 0 ? String(format: "%.2f", result.total) : "-"
        ]
        let xs: [CGFloat] = [36, 68, 105, 285, 470, 745]
        let widths = [26, 28, 170, 176, 260, 54]
        for index in values.indices {
            draw(String(values[index].prefix(widths[index])), x: xs[index], y: y, size: 8.5)
        }
    }

    private static func draw(_ text: String, x: CGFloat, y: CGFloat, size: CGFloat, weight: UIFont.Weight = .regular, color: UIColor = .black) {
        let font = UIFont.systemFont(ofSize: size, weight: weight)
        let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color]
        text.draw(at: CGPoint(x: x, y: y), withAttributes: attributes)
    }
}
