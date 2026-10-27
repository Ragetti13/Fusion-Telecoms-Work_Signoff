import UIKit

struct PDFGenerator {
    static func generate(from workOrder: WorkOrder) -> Data {
        let pageRect = CGRect(x: 0, y: 0, width: 595.2, height: 841.8) // A4
        let renderer = UIGraphicsPDFRenderer(bounds: pageRect)
        return renderer.pdfData { ctx in
            ctx.beginPage()
            draw(workOrder: workOrder, in: pageRect)

            let photos = workOrder.photos
            if !photos.isEmpty {
                drawPhotoPages(photos, in: pageRect, ctx: ctx)
            }
        }
    }

    // Lay out install photos on fresh A4 pages, four per page in a 2×2 grid.
    private static func drawPhotoPages(_ photos: [UIImage], in page: CGRect, ctx: UIGraphicsPDFRendererContext) {
        let margin: CGFloat = 50
        let brandPink = UIColor(red: 0.929, green: 0.059, blue: 0.400, alpha: 1.0)
        let perPage = 4
        let columns = 2
        let gutter: CGFloat = 16
        let headerHeight: CGFloat = 40
        let cellW = (page.width - margin * 2 - gutter) / CGFloat(columns)
        let gridTop = margin + headerHeight
        let cellH = (page.height - gridTop - margin - gutter) / 2

        var index = 0
        while index < photos.count {
            ctx.beginPage()
            // Page header
            NSAttributedString(string: "Installation Photos", attributes: [
                .font: UIFont.systemFont(ofSize: 16, weight: .bold),
                .foregroundColor: brandPink
            ]).draw(at: CGPoint(x: margin, y: margin))
            drawHRule(from: CGPoint(x: margin, y: margin + 28),
                      to: CGPoint(x: page.width - margin, y: margin + 28),
                      color: brandPink, width: 1)

            for slot in 0..<perPage where index < photos.count {
                let row = slot / columns
                let col = slot % columns
                let cellX = margin + CGFloat(col) * (cellW + gutter)
                let cellY = gridTop + CGFloat(row) * (cellH + gutter)
                let cell = CGRect(x: cellX, y: cellY, width: cellW, height: cellH)
                drawPhoto(photos[index], in: cell)
                index += 1
            }
        }
    }

    // Aspect-fit a photo within a cell, with a thin border.
    private static func drawPhoto(_ image: UIImage, in cell: CGRect) {
        let imgAspect = image.size.width / max(image.size.height, 1)
        let cellAspect = cell.width / cell.height
        var drawRect = cell
        if imgAspect > cellAspect {
            let h = cell.width / imgAspect
            drawRect = CGRect(x: cell.minX, y: cell.midY - h / 2, width: cell.width, height: h)
        } else {
            let w = cell.height * imgAspect
            drawRect = CGRect(x: cell.midX - w / 2, y: cell.minY, width: w, height: cell.height)
        }
        image.draw(in: drawRect)
        UIColor.systemGray4.setStroke()
        let border = UIBezierPath(rect: drawRect)
        border.lineWidth = 0.5
        border.stroke()
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

        // Installation details (only if captured)
        if workOrder.hasInstallDetails {
            NSAttributedString(string: "Installation Details", attributes: [
                .font: UIFont.systemFont(ofSize: 13, weight: .semibold),
                .foregroundColor: UIColor.black
            ]).draw(at: CGPoint(x: margin, y: y))
            y += 20

            var installRows: [(String, String)] = []
            if let serial = workOrder.serialNumber, !serial.isEmpty { installRows.append(("Router Serial:", serial)) }
            if let mac = workOrder.macAddress, !mac.isEmpty { installRows.append(("MAC Address:", mac)) }
            if let r = WorkOrder.speedText(down: workOrder.routerDownMbps, up: workOrder.routerUpMbps) { installRows.append(("Router Speed:", r)) }
            if let w = WorkOrder.speedText(down: workOrder.wifiDownMbps, up: workOrder.wifiUpMbps) { installRows.append(("Wi-Fi Speed:", w)) }
            for (label, value) in installRows {
                NSAttributedString(string: label, attributes: labelAttrs).draw(at: CGPoint(x: margin, y: y))
                NSAttributedString(string: value, attributes: valueAttrs).draw(at: CGPoint(x: margin + 130, y: y))
                y += 20
            }
            y += 14
        }

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
