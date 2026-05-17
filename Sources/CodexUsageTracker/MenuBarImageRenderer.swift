import AppKit

enum MenuBarImageRenderer {
    static func render(
        title: String,
        status: UsageStatus,
        iconMode: MenuBarIconMode,
        fontSize: MenuBarFontSize
    ) -> NSImage {
        let iconColor = status.nsColor
        let textColor = NSColor.black
        let font = NSFont.monospacedDigitSystemFont(ofSize: fontSize.pointSize, weight: .medium)
        let textAttributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: textColor
        ]
        let text = NSAttributedString(string: title, attributes: textAttributes)
        let textSize = text.size()
        let iconWidth = iconMode == .statusIcon ? fontSize.pointSize + 4 : 0
        let width = ceil(textSize.width + iconWidth)
        let height = max(18, ceil(textSize.height))
        let image = NSImage(size: NSSize(width: width, height: height))

        image.lockFocus()
        NSGraphicsContext.current?.imageInterpolation = .high

        var x: CGFloat = 0
        if iconMode == .statusIcon {
            let symbolConfig = NSImage.SymbolConfiguration(pointSize: fontSize.pointSize, weight: .semibold)
            let symbol = NSImage(systemSymbolName: status.symbolName, accessibilityDescription: nil)?
                .withSymbolConfiguration(symbolConfig)
            let symbolSize = symbol?.size ?? NSSize(width: fontSize.pointSize, height: fontSize.pointSize)
            let symbolRect = NSRect(
                x: 0,
                y: (height - symbolSize.height) / 2,
                width: symbolSize.width,
                height: symbolSize.height
            )
            iconColor.set()
            symbol?.draw(in: symbolRect, from: .zero, operation: .sourceOver, fraction: 1)
            x = symbolSize.width + 4
        }

        let textRect = NSRect(
            x: x,
            y: (height - textSize.height) / 2,
            width: textSize.width,
            height: textSize.height
        )
        text.draw(in: textRect)
        image.unlockFocus()
        image.isTemplate = false
        return image
    }
}
