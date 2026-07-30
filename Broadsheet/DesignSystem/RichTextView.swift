import SwiftUI

/// Renders semantic inline runs in the house style.
///
/// Links keep their text and become tappable; the publisher's original markup,
/// classes, and inline styles never reach this view.
public struct RichTextView: View {
    let richText: RichText
    let font: Font

    public init(_ richText: RichText, font: Font) {
        self.richText = richText
        self.font = font
    }

    public var body: some View {
        Text(attributed)
            .font(font)
            .foregroundStyle(BSColor.textPrimary)
            .tint(BSColor.accent)
            .lineSpacing(5)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var attributed: AttributedString {
        var output = AttributedString()
        for run in richText.runs {
            var piece = AttributedString(run.text)
            switch run {
            case .plain:
                break
            case .emphasis:
                piece.inlinePresentationIntent = .emphasized
            case .strong:
                piece.inlinePresentationIntent = .stronglyEmphasized
            case .link(_, let url):
                piece.link = url
                piece.underlineStyle = .single
                piece.foregroundColor = BSColor.accent
            }
            output.append(piece)
        }
        return output
    }
}
