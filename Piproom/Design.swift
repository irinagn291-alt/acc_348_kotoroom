import SwiftUI

struct SmallPrint: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View { Text(text.uppercased()).font(.caption2.monospaced().weight(.semibold)).tracking(1.6) }
}

struct Felt: View {
    var body: some View {
        ZStack {
            Color.felt
            Canvas { ctx, size in
                var lines = Path()
                for i in stride(from: -size.height, to: size.width, by: 7) {
                    lines.move(to: CGPoint(x: i, y: 0))
                    lines.addLine(to: CGPoint(x: i+size.height, y: size.height))
                }
                ctx.stroke(lines, with: .color(.paper.opacity(0.027)), lineWidth: 0.65)
            }
        }.ignoresSafeArea().accessibilityHidden(true)
    }
}

// Printed topographic lines on the sleeve that holds the monthly contact sheet.
struct Contours: View {
    var body: some View {
        Canvas { ctx, s in
            for band in 0..<28 {
                var p = Path()
                for x in stride(from: 0.0, through: s.width + 3, by: 3) {
                    let t = x / max(s.width, 1)
                    let y = s.height * (0.42 + 0.16 * sin(t * 5.7) + 0.065 * cos(t * 13 + Double(band) * 0.04)) + Double(band) * 4
                    if x == 0 { p.move(to: .init(x: x, y: y)) } else { p.addLine(to: .init(x: x, y: y)) }
                }
                ctx.stroke(p, with: .color(.felt.opacity(0.62)), lineWidth: 0.8)
            }
        }.accessibilityHidden(true)
    }
}

struct PrimaryLabel: View {
    let text: String
    var icon = "arrow.right"
    var body: some View {
        HStack { Text(text).font(.headline); Spacer(); Image(systemName: icon) }
            .padding(.horizontal, 16).padding(.vertical, 14)
            .foregroundStyle(Color.paper).background(Color.felt, in: RoundedRectangle(cornerRadius: 12))
    }
}

struct PaperCard<Content: View>: View {
    @ViewBuilder var content: () -> Content
    var body: some View {
        VStack(alignment: .leading, spacing: 12, content: content)
            .padding(18).frame(maxWidth: .infinity, alignment: .leading)
            .foregroundStyle(Color.ink).background(Color.paper, in: RoundedRectangle(cornerRadius: 20))
    }
}

struct MenuRow: View {
    let title: String
    let note: String
    let icon: String
    var value: String?
    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: icon).font(.title3).frame(width: 30)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.headline)
                Text(note).font(.caption).foregroundStyle(Color.faded)
            }
            Spacer()
            if let value { Text(value).font(.title3.monospacedDigit()) }
            Image(systemName: "chevron.right").font(.caption)
        }.padding(.vertical, 12).contentShape(Rectangle())
    }
}
