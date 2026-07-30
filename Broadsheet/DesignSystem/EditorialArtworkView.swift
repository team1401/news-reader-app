import SwiftUI

/// Draws the demo edition's illustrations natively.
///
/// The prototype used inline vector art rather than photography, and so does the
/// app: nothing here is a photograph, so nothing can imply a real scene or carry a
/// wire-service credit. Publisher photography, when a real feed supplies it, is
/// rendered unmodified — no warming filters are applied to editorial images.
public struct EditorialArtworkView: View {
    let artwork: EditorialArtwork

    public init(_ artwork: EditorialArtwork) {
        self.artwork = artwork
    }

    public var body: some View {
        GeometryReader { proxy in
            Canvas { context, size in
                draw(in: &context, size: size)
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
        .background(skyGradient)
        .accessibilityHidden(true)
    }

    // MARK: Palettes

    private struct Palette {
        let skyTop: Color
        let skyBottom: Color
        let far: Color
        let mid: Color
        let near: Color
        let ink: Color
        let highlight: Color
    }

    private var palette: Palette {
        switch artwork {
        case .duskTransmissionLines:
            return Palette(skyTop: hex(0x6E7F92), skyBottom: hex(0xD9A277), far: hex(0x8A8471),
                           mid: hex(0x6B6A5C), near: hex(0x494A44), ink: hex(0x2B2B29), highlight: hex(0xF3E2BE))
        case .harborGantries:
            return Palette(skyTop: hex(0x9FB0BD), skyBottom: hex(0xE3E1D8), far: hex(0x8E9AA0),
                           mid: hex(0x6C7880), near: hex(0x424C55), ink: hex(0x2A3138), highlight: hex(0xF6F2E6))
        case .riverDelta:
            return Palette(skyTop: hex(0x8FA88C), skyBottom: hex(0xD8D2B6), far: hex(0x9BAE86),
                           mid: hex(0x77906B), near: hex(0x4E6350), ink: hex(0x33403A), highlight: hex(0xBFD6DA))
        case .statehouseSteps:
            return Palette(skyTop: hex(0x9BA9B8), skyBottom: hex(0xE6E2D6), far: hex(0xC4BCA9),
                           mid: hex(0xA79C87), near: hex(0x7C7460), ink: hex(0x3A3730), highlight: hex(0xF2ECDD))
        case .nightClinic:
            return Palette(skyTop: hex(0x22293A), skyBottom: hex(0x3A4152), far: hex(0x2E3547),
                           mid: hex(0x272D3C), near: hex(0x1B2029), ink: hex(0x11151B), highlight: hex(0xE9C87A))
        case .classroomWindows:
            return Palette(skyTop: hex(0xA8B6BE), skyBottom: hex(0xE9E4D6), far: hex(0xC0B49C),
                           mid: hex(0x9E9078), near: hex(0x6E6455), ink: hex(0x342F27), highlight: hex(0xF4E9C5))
        case .rowHouses:
            return Palette(skyTop: hex(0x8D9CAA), skyBottom: hex(0xE7DFD0), far: hex(0xB99C86),
                           mid: hex(0x9A7C69), near: hex(0x6D584C), ink: hex(0x33291F), highlight: hex(0xF0E3CE))
        case .rangeRoad:
            return Palette(skyTop: hex(0x93A6B4), skyBottom: hex(0xE2DAC6), far: hex(0xB5AE93),
                           mid: hex(0x92906F), near: hex(0x6B6B55), ink: hex(0x39392E), highlight: hex(0xF4EEDC))
        }
    }

    private func hex(_ value: UInt32) -> Color {
        Color(uiColor: UIColor(hex: value))
    }

    private var skyGradient: LinearGradient {
        LinearGradient(
            colors: [palette.skyTop, palette.skyBottom],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    // MARK: Composition

    private func draw(in context: inout GraphicsContext, size: CGSize) {
        switch artwork {
        case .duskTransmissionLines:
            sun(&context, size: size, at: CGPoint(x: size.width * 0.68, y: size.height * 0.42), radius: size.height * 0.12)
            ridges(&context, size: size)
            pylons(&context, size: size)
        case .rangeRoad:
            ridges(&context, size: size)
            road(&context, size: size)
            poles(&context, size: size)
        case .harborGantries:
            water(&context, size: size)
            gantries(&context, size: size)
        case .riverDelta:
            ridges(&context, size: size)
            braidedChannels(&context, size: size)
        case .rowHouses, .statehouseSteps, .classroomWindows, .nightClinic:
            ridges(&context, size: size)
            skyline(&context, size: size)
        }
    }

    private func sun(_ context: inout GraphicsContext, size: CGSize, at center: CGPoint, radius: CGFloat) {
        let rect = CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)
        context.fill(Path(ellipseIn: rect), with: .color(palette.highlight.opacity(0.9)))
    }

    private func ridges(_ context: inout GraphicsContext, size: CGSize) {
        let layers: [(color: Color, baseline: CGFloat, amplitude: CGFloat, phase: CGFloat)] = [
            (palette.far, 0.62, 0.10, 0.0),
            (palette.mid, 0.75, 0.08, 1.3),
            (palette.near, 0.88, 0.06, 2.4)
        ]

        for layer in layers {
            var path = Path()
            path.move(to: CGPoint(x: 0, y: size.height))
            let steps = 24
            for step in 0...steps {
                let progress = CGFloat(step) / CGFloat(steps)
                let x = progress * size.width
                let wave = sin(progress * 3.4 + layer.phase) * 0.5 + cos(progress * 6.1 + layer.phase) * 0.5
                let y = size.height * (layer.baseline + wave * layer.amplitude * 0.5)
                path.addLine(to: CGPoint(x: x, y: y))
            }
            path.addLine(to: CGPoint(x: size.width, y: size.height))
            path.closeSubpath()
            context.fill(path, with: .color(layer.color))
        }
    }

    private func pylons(_ context: inout GraphicsContext, size: CGSize) {
        let positions: [CGFloat] = [0.22, 0.55, 0.86]
        let topY = size.height * 0.28
        var cableTops: [CGPoint] = []

        for position in positions {
            let x = size.width * position
            let baseY = size.height * 0.80
            let halfWidth = size.width * 0.045

            var frame = Path()
            frame.move(to: CGPoint(x: x - halfWidth, y: baseY))
            frame.addLine(to: CGPoint(x: x, y: topY))
            frame.addLine(to: CGPoint(x: x + halfWidth, y: baseY))
            context.stroke(frame, with: .color(palette.ink), lineWidth: 1.6)

            var crossArm = Path()
            crossArm.move(to: CGPoint(x: x - halfWidth * 1.3, y: topY + size.height * 0.08))
            crossArm.addLine(to: CGPoint(x: x + halfWidth * 1.3, y: topY + size.height * 0.08))
            context.stroke(crossArm, with: .color(palette.ink), lineWidth: 1.4)

            var brace = Path()
            brace.move(to: CGPoint(x: x - halfWidth * 0.6, y: baseY - size.height * 0.16))
            brace.addLine(to: CGPoint(x: x + halfWidth * 0.6, y: baseY - size.height * 0.30))
            brace.move(to: CGPoint(x: x + halfWidth * 0.6, y: baseY - size.height * 0.16))
            brace.addLine(to: CGPoint(x: x - halfWidth * 0.6, y: baseY - size.height * 0.30))
            context.stroke(brace, with: .color(palette.ink.opacity(0.7)), lineWidth: 1)

            cableTops.append(CGPoint(x: x, y: topY + size.height * 0.08))
        }

        for index in 0..<(cableTops.count - 1) {
            let start = cableTops[index]
            let end = cableTops[index + 1]
            for offset in [-size.width * 0.05, CGFloat(0), size.width * 0.05] {
                var cable = Path()
                cable.move(to: CGPoint(x: start.x + offset, y: start.y))
                cable.addQuadCurve(
                    to: CGPoint(x: end.x + offset, y: end.y),
                    control: CGPoint(x: (start.x + end.x) / 2 + offset, y: start.y + size.height * 0.09)
                )
                context.stroke(cable, with: .color(palette.ink.opacity(0.55)), lineWidth: 0.9)
            }
        }
    }

    private func road(_ context: inout GraphicsContext, size: CGSize) {
        var path = Path()
        path.move(to: CGPoint(x: size.width * 0.36, y: size.height))
        path.addQuadCurve(
            to: CGPoint(x: size.width * 0.58, y: size.height * 0.66),
            control: CGPoint(x: size.width * 0.40, y: size.height * 0.80)
        )
        path.addLine(to: CGPoint(x: size.width * 0.62, y: size.height * 0.66))
        path.addQuadCurve(
            to: CGPoint(x: size.width * 0.62, y: size.height),
            control: CGPoint(x: size.width * 0.52, y: size.height * 0.82)
        )
        path.closeSubpath()
        context.fill(path, with: .color(palette.highlight.opacity(0.55)))
    }

    private func poles(_ context: inout GraphicsContext, size: CGSize) {
        for position in stride(from: 0.12, through: 0.92, by: 0.16) {
            let x = size.width * CGFloat(position)
            let height = size.height * (0.20 + CGFloat(position) * 0.06)
            let baseY = size.height * 0.86
            var pole = Path()
            pole.move(to: CGPoint(x: x, y: baseY))
            pole.addLine(to: CGPoint(x: x, y: baseY - height))
            context.stroke(pole, with: .color(palette.ink.opacity(0.8)), lineWidth: 1.4)

            var arm = Path()
            arm.move(to: CGPoint(x: x - size.width * 0.018, y: baseY - height + 4))
            arm.addLine(to: CGPoint(x: x + size.width * 0.018, y: baseY - height + 4))
            context.stroke(arm, with: .color(palette.ink.opacity(0.8)), lineWidth: 1.2)
        }
    }

    private func water(_ context: inout GraphicsContext, size: CGSize) {
        var sea = Path()
        sea.addRect(CGRect(x: 0, y: size.height * 0.72, width: size.width, height: size.height * 0.28))
        context.fill(sea, with: .color(palette.near))

        for index in 0..<5 {
            let y = size.height * (0.76 + CGFloat(index) * 0.045)
            var ripple = Path()
            ripple.move(to: CGPoint(x: size.width * 0.08, y: y))
            ripple.addLine(to: CGPoint(x: size.width * (0.30 + CGFloat(index) * 0.10), y: y))
            context.stroke(ripple, with: .color(palette.highlight.opacity(0.18)), lineWidth: 1)
        }
    }

    private func gantries(_ context: inout GraphicsContext, size: CGSize) {
        let quayY = size.height * 0.72

        for position in [0.20, 0.46, 0.72] {
            let x = size.width * CGFloat(position)
            let topY = size.height * 0.26
            let span = size.width * 0.12

            var frame = Path()
            frame.move(to: CGPoint(x: x - span * 0.5, y: quayY))
            frame.addLine(to: CGPoint(x: x - span * 0.35, y: topY))
            frame.addLine(to: CGPoint(x: x + span * 0.35, y: topY))
            frame.addLine(to: CGPoint(x: x + span * 0.5, y: quayY))
            context.stroke(frame, with: .color(palette.ink), lineWidth: 2)

            // Cross-brace between the legs, so the crane reads as a structure.
            var brace = Path()
            brace.move(to: CGPoint(x: x - span * 0.44, y: quayY - size.height * 0.16))
            brace.addLine(to: CGPoint(x: x + span * 0.44, y: quayY - size.height * 0.16))
            context.stroke(brace, with: .color(palette.ink.opacity(0.7)), lineWidth: 1.2)

            var boom = Path()
            boom.move(to: CGPoint(x: x - span * 0.85, y: topY + size.height * 0.03))
            boom.addLine(to: CGPoint(x: x + span * 1.25, y: topY - size.height * 0.02))
            context.stroke(boom, with: .color(palette.ink), lineWidth: 2.4)

            var hoist = Path()
            hoist.move(to: CGPoint(x: x + span * 0.75, y: topY))
            hoist.addLine(to: CGPoint(x: x + span * 0.75, y: topY + size.height * 0.14))
            context.stroke(hoist, with: .color(palette.ink.opacity(0.6)), lineWidth: 1)
        }

        // Quay edge, then a vessel sitting in the water below it.
        var quay = Path()
        quay.addRect(CGRect(x: 0, y: quayY, width: size.width, height: size.height * 0.02))
        context.fill(quay, with: .color(palette.ink.opacity(0.6)))

        var hull = Path()
        hull.move(to: CGPoint(x: size.width * 0.08, y: size.height * 0.79))
        hull.addLine(to: CGPoint(x: size.width * 0.70, y: size.height * 0.79))
        hull.addLine(to: CGPoint(x: size.width * 0.63, y: size.height * 0.87))
        hull.addLine(to: CGPoint(x: size.width * 0.15, y: size.height * 0.87))
        hull.closeSubpath()
        context.fill(hull, with: .color(palette.ink.opacity(0.85)))

        for index in 0..<6 {
            let container = CGRect(
                x: size.width * (0.14 + CGFloat(index) * 0.085),
                y: size.height * 0.755,
                width: size.width * 0.07,
                height: size.height * 0.035
            )
            context.fill(Path(container), with: .color(palette.highlight.opacity(index % 2 == 0 ? 0.5 : 0.3)))
        }
    }

    private func braidedChannels(_ context: inout GraphicsContext, size: CGSize) {
        for index in 0..<4 {
            let offset = CGFloat(index) * size.height * 0.055
            var channel = Path()
            channel.move(to: CGPoint(x: 0, y: size.height * 0.72 + offset))
            channel.addCurve(
                to: CGPoint(x: size.width, y: size.height * 0.60 + offset),
                control1: CGPoint(x: size.width * 0.35, y: size.height * 0.86 + offset),
                control2: CGPoint(x: size.width * 0.62, y: size.height * 0.50 + offset)
            )
            context.stroke(channel, with: .color(palette.highlight.opacity(0.65)), lineWidth: 3 - CGFloat(index) * 0.5)
        }
    }

    private func skyline(_ context: inout GraphicsContext, size: CGSize) {
        var x: CGFloat = size.width * 0.06
        var index = 0
        while x < size.width * 0.94 {
            let width = size.width * (0.09 + CGFloat(index % 3) * 0.02)
            let height = size.height * (0.24 + CGFloat((index * 7) % 5) * 0.04)
            let rect = CGRect(x: x, y: size.height * 0.80 - height, width: width, height: height)
            context.fill(Path(rect), with: .color(index % 2 == 0 ? palette.mid : palette.near))

            var roof = Path()
            roof.move(to: CGPoint(x: rect.minX - 2, y: rect.minY))
            roof.addLine(to: CGPoint(x: rect.midX, y: rect.minY - size.height * 0.05))
            roof.addLine(to: CGPoint(x: rect.maxX + 2, y: rect.minY))
            roof.closeSubpath()
            context.fill(roof, with: .color(palette.ink.opacity(0.7)))

            for row in 0..<3 {
                for column in 0..<2 {
                    let windowRect = CGRect(
                        x: rect.minX + width * (0.22 + CGFloat(column) * 0.38),
                        y: rect.minY + height * (0.22 + CGFloat(row) * 0.24),
                        width: width * 0.20,
                        height: height * 0.13
                    )
                    context.fill(Path(windowRect), with: .color(palette.highlight.opacity(0.55)))
                }
            }

            x += width + size.width * 0.03
            index += 1
        }
    }
}

#Preview {
    ScrollView {
        VStack(spacing: 12) {
            ForEach(EditorialArtwork.allCases, id: \.self) { artwork in
                EditorialArtworkView(artwork)
                    .aspectRatio(16.0 / 9.0, contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            }
        }
        .padding()
    }
}
