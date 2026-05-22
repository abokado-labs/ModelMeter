import AppKit

enum MenuBarImageRenderer {
    static func render(
        title: String,
        status: UsageStatus,
        iconMode: MenuBarIconMode,
        fontSize: MenuBarFontSize,
        labelStyle: MenuBarLabelStyle,
        codexWarning: Bool,
        claudeWarning: Bool
    ) -> NSImage {
        let font = NSFont.monospacedDigitSystemFont(ofSize: fontSize.pointSize, weight: .medium)
        let textAttributes = attributes(font: font, color: .labelColor)
        let warningAttributes = attributes(font: font, color: .systemRed)
        let parts = parse(title: title)
        let statusIconWidth = iconMode == .statusIcon ? fontSize.pointSize + 5 : 0
        let providerIconSize = fontSize.pointSize + 2
        let partGap: CGFloat = parts.count > 1 ? 10 : 0

        var width = statusIconWidth
        for (index, part) in parts.enumerated() {
            if index > 0 { width += partGap }
            if labelStyle == .icons, part.provider != nil {
                width += providerIconSize + 3
            } else {
                width += ceil(NSAttributedString(string: part.label, attributes: textAttributes).size().width) + 3
            }
            let attrs = part.warning ? warningAttributes : textAttributes
            width += ceil(NSAttributedString(string: part.value, attributes: attrs).size().width)
        }

        if parts.isEmpty {
            width += ceil(NSAttributedString(string: title, attributes: textAttributes).size().width)
        }

        let height = max(18, ceil(font.ascender - font.descender + 2))
        let imageSize = NSSize(width: ceil(width), height: height)
        let image = NSImage(size: imageSize, flipped: false) { rect in
            NSGraphicsContext.current?.imageInterpolation = .high

            let textAttributes = attributes(font: font, color: .labelColor)
            let warningAttributes = attributes(font: font, color: .systemRed)
            var x: CGFloat = 0
            if iconMode == .statusIcon {
                let symbolConfig = NSImage.SymbolConfiguration(pointSize: fontSize.pointSize, weight: .semibold)
                let symbol = NSImage(systemSymbolName: status.symbolName, accessibilityDescription: nil)?
                    .withSymbolConfiguration(symbolConfig)
                let symbolSize = symbol?.size ?? NSSize(width: fontSize.pointSize, height: fontSize.pointSize)
                let symbolRect = NSRect(
                    x: 0,
                    y: (rect.height - symbolSize.height) / 2,
                    width: symbolSize.width,
                    height: symbolSize.height
                )
                status.nsColor.set()
                symbol?.draw(in: symbolRect, from: .zero, operation: .sourceOver, fraction: 1)
                x = symbolSize.width + 5
            }

            if parts.isEmpty {
                NSString(string: title).draw(at: NSPoint(x: x, y: textBaselineY(font: font, height: rect.height)), withAttributes: textAttributes)
            } else {
                for (index, part) in parts.enumerated() {
                    if index > 0 { x += partGap }
                    if labelStyle == .icons, let provider = part.provider, let icon = providerImage(provider, size: providerIconSize) {
                        let iconRect = providerIconRect(
                            provider: provider,
                            x: x,
                            containerHeight: rect.height,
                            size: providerIconSize
                        )
                        drawTemplateIcon(icon, in: iconRect, color: .labelColor)
                        x += providerIconSize + 3
                    } else {
                        let label = NSAttributedString(string: part.label, attributes: textAttributes)
                        NSString(string: part.label).draw(at: NSPoint(x: x, y: textBaselineY(font: font, height: rect.height)), withAttributes: textAttributes)
                        x += ceil(label.size().width) + 3
                    }

                    let attrs = part.warning ? warningAttributes : textAttributes
                    NSString(string: part.value).draw(at: NSPoint(x: x, y: textBaselineY(font: font, height: rect.height)), withAttributes: attrs)
                    x += ceil(NSAttributedString(string: part.value, attributes: attrs).size().width)
                }
            }

            return true
        }
        image.isTemplate = false
        return image
    }

    private struct MenuBarPart {
        let provider: Provider?
        let label: String
        let value: String
        let warning: Bool
    }

    private enum Provider {
        case codex
        case claude
        case gemini
    }

    private static func parse(title: String) -> [MenuBarPart] {
        title.components(separatedBy: "  ").compactMap { rawPart in
            let fields = rawPart.split(separator: " ", maxSplits: 1).map(String.init)
            guard fields.count == 2 else { return nil }
            switch fields[0] {
            case "C":
                return MenuBarPart(provider: .codex, label: "C", value: fields[1], warning: false)
            case "Cl":
                return MenuBarPart(provider: .claude, label: "Cl", value: fields[1], warning: false)
            case "C!":
                return MenuBarPart(provider: .codex, label: "C", value: fields[1], warning: true)
            case "Cl!":
                return MenuBarPart(provider: .claude, label: "Cl", value: fields[1], warning: true)
            case "G":
                return MenuBarPart(provider: .gemini, label: "G", value: fields[1], warning: false)
            case "G!":
                return MenuBarPart(provider: .gemini, label: "G", value: fields[1], warning: true)
            default:
                return nil
            }
        }
    }

    private static func attributes(font: NSFont, color: NSColor) -> [NSAttributedString.Key: Any] {
        [
            .font: font,
            .foregroundColor: color
        ]
    }

    private static func providerIconRect(provider: Provider, x: CGFloat, containerHeight: CGFloat, size: CGFloat) -> NSRect {
        let yOffset: CGFloat
        switch provider {
        case .codex:
            yOffset = 0
        case .claude:
            yOffset = 0
        case .gemini:
            yOffset = 1.5
        }
        return NSRect(
            x: x,
            y: round((containerHeight - size) / 2) + yOffset,
            width: size,
            height: size
        )
    }

    private static func providerImage(_ provider: Provider, size: CGFloat) -> NSImage? {
        let resourceName: String
        switch provider {
        case .codex:
            resourceName = "ChatGPT-Logo"
        case .claude:
            resourceName = "claude-transparent-custom"
        case .gemini:
            resourceName = "google-gemini-logomark-black-24439_32"
        }
        guard let url = Bundle.main.url(forResource: resourceName, withExtension: "png"),
              let source = NSImage(contentsOf: url)
        else {
            return nil
        }
        let image = NSImage(size: NSSize(width: size, height: size))
        image.lockFocus()
        NSGraphicsContext.current?.imageInterpolation = .high
        source.draw(in: NSRect(x: 0, y: 0, width: size, height: size), from: .zero, operation: .sourceOver, fraction: 1)
        image.unlockFocus()
        image.isTemplate = false
        return image
    }

    private static func drawTemplateIcon(_ icon: NSImage, in rect: NSRect, color: NSColor) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        context.saveGState()
        icon.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1)
        color.setFill()
        rect.fill(using: .sourceIn)
        context.restoreGState()
    }

    private static func textBaselineY(font: NSFont, height: CGFloat) -> CGFloat {
        // Menu bar text looks optically high when mathematically centered next to template icons.
        floor((height - font.ascender + font.descender) / 2 - font.descender - 1)
    }
}
