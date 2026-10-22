import UIKit

struct PDFGenerator {
    static func generate(from workOrder: WorkOrder) -> Data {
        let pageRect = CGRect(x: 0, y: 0, width: 595.2, height: 841.8) // A4
        let renderer = UIGraphicsPDFRenderer(bounds: pageRect)
        return renderer.pdfData { ctx in
            ctx.beginPage()
            draw(workOrder: workOrder, in: pageRect)
        }
    }

    private static func draw(workOrder: WorkOrder, in page: CGRect) {
        let margin: CGFloat = 50
        var y: CGFloat = margin

        // Header — Fusion logo + certificate title
        let brandPink = UIColor(red: 0.929, green: 0.059, blue: 0.400, alpha: 1.0)
        let logoSize: CGFloat = 58
        if let logo = UIImage(named: "Logo") {
            logo.draw(in: CGRect(x: margin, y: y, width: logoSize, height: logoSize))
        }
        let headX = margin + logoSize + 16
        NSAttributedString(string: "Work Completion Certificate", attributes: [
            .font: UIFont.systemFont(ofSize: 20, weight: .bold),
            .foregroundColor: brandPink
        ]).draw(at: CGPoint(x: headX, y: y + 8))
        NSAttributedString(string: "Fusion Telecoms", attributes: [
            .font: UIFont.systemFont(ofSize: 12),
            .foregroundColor: UIColor.darkGray
        ]).draw(at: CGPoint(x: headX, y: y + 36))
        y += logoSize + 14

        // Brand rule
        drawHRule(from: CGPoint(x: margin, y: y), to: CGPoint(x: page.width - margin, y: y), color: brandPink, width: 2)
        y += 22

        // Fields
        let fieldPairs: [(String, String)] = [
            ("Job Reference:", workOrder.jobReference.isEmpty ? "N/A" : workOrder.jobReference),
            ("Customer:",      workOrder.customerName),
            ("Site Address:",  workOrder.customerAddress.isEmpty ? "N/A" : workOrder.customerAddress),
            ("Date Completed:", workOrder.completedDate.formatted(date: .long, time: .shortened)),
            ("Technician:",    workOrder.technicianName.isEmpty ? "N/A" : workOrder.technicianName),
        ]

        let labelAttrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 11, weight: .semibold),
            .foregroundColor: UIColor.darkGray
        ]
        let valueAttrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 11),
            .foregroundColor: UIColor.black
        ]

        for (label, value) in fieldPairs {
            NSAttributedString(string: label, attributes: labelAttrs).draw(at: CGPoint(x: margin, y: y))
            NSAttributedString(string: value, attributes: valueAttrs).draw(at: CGPoint(x: margin + 130, y: y))
            y += 20
        }

        y += 14

        // Work description
        let sectionAttrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 13, weight: .semibold),
            .foregroundColor: UIColor.black
        ]
        NSAttributedString(string: "Work Completed", attributes: sectionAttrs).draw(at: CGPoint(x: margin, y: y))
        y += 20

        let descAttrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 11),
            .foregroundColor: UIColor.darkGray
        ]
        let descWidth = page.width - margin * 2
        let descStr = NSAttributedString(string: workOrder.workDescription, attributes: descAttrs)
        let descBounds = descStr.boundingRect(
            with: CGSize(width: descWidth, height: .greatestFiniteMagnitude),
            options: .usesLineFragmentOrigin, context: nil
        )
        descStr.draw(in: CGRect(x: margin, y: y, width: descWidth, height: descBounds.height))
        y += descBounds.height + 24

        // Rule
        drawHRule(from: CGPoint(x: margin, y: y), to: CGPoint(x: page.width - margin, y: y), color: .systemGray4, width: 1)
        y += 20

        // Signature section
        NSAttributedString(string: "Customer Sign-Off", attributes: sectionAttrs).draw(at: CGPoint(x: margin, y: y))
        y += 18

        let consentText = "I confirm that the above work has been completed satisfactorily."
        NSAttributedString(string: consentText, attributes: descAttrs).draw(at: CGPoint(x: margin, y: y))
        y += 26

        if let sigImage = workOrder.signatureImage {
            let sigRect = CGRect(x: margin, y: y, width: 220, height: 88)
            sigImage.draw(in: sigRect)
            y += 98
        }

        // Signature line
        drawHRule(from: CGPoint(x: margin, y: y), to: CGPoint(x: margin + 250, y: y), color: .black, width: 0.5)
        y += 6
        NSAttributedString(string: "Customer Signature", attributes: descAttrs).draw(at: CGPoint(x: margin, y: y))

        // Footer
        let footerAttrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 8),
            .foregroundColor: UIColor.systemGray
        ]
        let year = Calendar.current.component(.year, from: Date())
        let footerText = "© \(year) Fusion Telecoms LTD  |  fusion-telecoms.com  |  \(Date().formatted(date: .abbreviated, time: .shortened))"
        NSAttributedString(string: footerText, attributes: footerAttrs)
            .draw(at: CGPoint(x: margin, y: page.height - 36))
    }

    private static func drawHRule(from start: CGPoint, to end: CGPoint, color: UIColor, width: CGFloat) {
        let path = UIBezierPath()
        path.move(to: start)
        path.addLine(to: end)
        color.setStroke()
        path.lineWidth = width
        path.stroke()
    }
}
