import SwiftUI

extension Color {
    static let felt = Color(red: 0.063, green: 0.212, blue: 0.173)
    static let table = Color(red: 0.09, green: 0.275, blue: 0.22)
    static let paper = Color(red: 0.961, green: 0.918, blue: 0.82)
    static let faded = Color(red: 0.74, green: 0.80, blue: 0.72)
    static let ink = Color(red: 0.13, green: 0.16, blue: 0.135)
    static let enamel = Color(red: 0.64, green: 0.16, blue: 0.13)
    static let graphite = Color(white: 0.105)
}

struct Die: View {
    var body: some View {
        Canvas { ctx, size in
            let unit = min(size.width, size.height) / 100
            ctx.translateBy(x: (size.width - 100 * unit)/2, y: (size.height - 100 * unit)/2)
            ctx.scaleBy(x: unit, y: unit)
            let top = CGPoint(x: 49, y: 6), left = CGPoint(x: 5, y: 26)
            let mid = CGPoint(x: 51, y: 49), right = CGPoint(x: 95, y: 28)
            let bottomLeft = CGPoint(x: 8, y: 73), bottom = CGPoint(x: 53, y: 96), bottomRight = CGPoint(x: 92, y: 75)
            func face(_ points: [CGPoint], _ color: Color) {
                var path = Path(); path.move(to: points[0]); points.dropFirst().forEach { path.addLine(to: $0) }; path.closeSubpath()
                ctx.fill(path, with: .color(color)); ctx.stroke(path, with: .color(.ink.opacity(0.85)), style: StrokeStyle(lineWidth: 1.6, lineJoin: .round))
            }
            face([top,right,mid,left], .paper)
            face([left,mid,bottom,bottomLeft], Color(red: 0.88, green: 0.81, blue: 0.67))
            face([mid,right,bottomRight,bottom], Color(red: 0.72, green: 0.68, blue: 0.55))
            func pip(_ x: Double, _ y: Double, _ w: Double, _ h: Double, _ angle: Double, _ color: Color) {
                var c = ctx; c.translateBy(x: x, y: y); c.rotate(by: .degrees(angle))
                c.fill(Path(ellipseIn: CGRect(x: -w/2, y: -h/2, width: w, height: h)), with: .color(color))
            }
            pip(50,27,19,10,1,.enamel)
            for (x,y) in [(17,45),(29,61),(42,78)] { pip(Double(x),Double(y),7,10,-21,.ink) }
            for (x,y) in [(62,53),(83,43),(72,62),(62,78),(82,69)] { pip(Double(x),Double(y),6.5,10,19,.ink) }
        }.accessibilityHidden(true)
    }
}


// Six divisions echo the die while the fill still represents exact review progress.
struct ContactMeter: View {
    let reviewed: Int
    let total: Int
    var tint: Color
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        let fraction = min(1, max(0, Double(reviewed) / Double(max(1, total))))
        HStack(spacing: 3) {
            ForEach(0..<6) { index in
                GeometryReader { proxy in
                    ZStack(alignment: .leading) {
                        Capsule().fill(tint.opacity(0.22))
                        Capsule().fill(tint).frame(width: proxy.size.width * min(1, max(0, fraction * 6 - Double(index))))
                    }
                }
            }
        }.frame(height: 4)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.25), value: fraction)
            .accessibilityHidden(true)
    }
}
