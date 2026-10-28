//
//  SolarIcons.swift
//  AppwinSupport
//
//  Solar "Linear" icons, the same glyphs as the dashboard (`@solar-icons/react`).

import SwiftUI

/// Solar Linear icon (24x24 viewBox, Close is 16x16), 1.5 stroke.
struct SolarIcon: View {
    enum Kind {
        case plain2
        case inbox
        case altArrowRight
        case altArrowLeft
        case altArrowDown
        case close
        case infoCircle
        case paperclip
        case gallery
        case videoLibrary
        case pen
        case closeCircle
        case playCircle
        case document
        case arrowUp
        case smileCircle
    }

    let kind: Kind
    var color: Color = .primary
    var size: CGFloat = 16

    var body: some View {
        Canvas { context, canvasSize in
            let scale = min(canvasSize.width, canvasSize.height) / kind.viewBox
            var transform = CGAffineTransform(scaleX: scale, y: scale)

            for element in kind.elements {
                switch element {
                case .stroke(let d, let lineWidth, let roundCaps):
                    var path = Path(svgPath: d)
                    path = path.applying(transform)
                    context.stroke(
                        path,
                        with: .color(color),
                        style: StrokeStyle(
                            lineWidth: lineWidth * scale,
                            lineCap: roundCaps ? .round : .butt,
                            lineJoin: .round
                        )
                    )
                case .circleStroke(let cx, let cy, let r, let lineWidth):
                    let rect = CGRect(
                        x: (cx - r) * scale,
                        y: (cy - r) * scale,
                        width: r * 2 * scale,
                        height: r * 2 * scale
                    )
                    context.stroke(
                        Path(ellipseIn: rect),
                        with: .color(color),
                        style: StrokeStyle(lineWidth: lineWidth * scale)
                    )
                case .circleFill(let cx, let cy, let r):
                    let rect = CGRect(
                        x: (cx - r) * scale,
                        y: (cy - r) * scale,
                        width: r * 2 * scale,
                        height: r * 2 * scale
                    )
                    context.fill(Path(ellipseIn: rect), with: .color(color))
                }
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

private extension SolarIcon.Kind {
    var viewBox: CGFloat { self == .close ? 16 : 24 }

    enum Element {
        case stroke(String, lineWidth: CGFloat = 1.5, roundCaps: Bool = false)
        case circleStroke(cx: CGFloat, cy: CGFloat, r: CGFloat, lineWidth: CGFloat = 1.5)
        case circleFill(cx: CGFloat, cy: CGFloat, r: CGFloat)
    }

    var elements: [Element] {
        switch self {
        case .plain2:
            return [
                .stroke("""
                M17.4975 18.4851L20.6281 9.09373C21.8764 5.34874 22.5006 3.47624 \
                21.5122 2.48782C20.5237 1.49939 18.6511 2.12356 14.906 3.37189L5.57477 \
                6.48218C3.49295 7.1761 2.45203 7.52305 2.13608 8.28637C2.06182 8.46577 \
                2.01692 8.65596 2.00311 8.84963C1.94433 9.67365 2.72018 10.4495 4.27188 \
                12.0011L4.55451 12.2837C4.80921 12.5384 4.93655 12.6658 5.03282 12.8075C5.22269 \
                13.0871 5.33046 13.4143 5.34393 13.7519C5.35076 13.9232 5.32403 14.1013 \
                5.27057 14.4574C5.07488 15.7612 4.97703 16.4131 5.0923 16.9147C5.32205 \
                17.9146 6.09599 18.6995 7.09257 18.9433C7.59255 19.0656 8.24576 18.977 \
                9.5522 18.7997L9.62363 18.79C9.99191 18.74 10.1761 18.715 10.3529 18.7257C10.6738 \
                18.745 10.9838 18.8496 11.251 19.0285C11.3981 19.1271 11.5295 19.2585 \
                11.7923 19.5213L12.0436 19.7725C13.5539 21.2828 14.309 22.0379 15.1101 \
                21.9985C15.3309 21.9877 15.5479 21.9365 15.7503 21.8474C16.4844 21.5244 \
                16.8221 20.5113 17.4975 18.4851Z
                """),
                .stroke("M6 18L21 3", roundCaps: true),
            ]
        case .inbox:
            return [
                .stroke("""
                M2 12C2 7.28595 2 4.92893 3.46447 3.46447C4.92893 2 7.28595 2 12 2C16.714 \
                2 19.0711 2 20.5355 3.46447C22 4.92893 22 7.28595 22 12C22 16.714 22 \
                19.0711 20.5355 20.5355C19.0711 22 16.714 22 12 22C7.28595 22 4.92893 22 \
                3.46447 20.5355C2 19.0711 2 16.714 2 12Z
                """),
                .stroke("""
                M2 13H5.16026C6.06543 13 6.51802 13 6.91584 13.183C7.31367 13.3659 \
                7.60821 13.7096 8.19729 14.3968L8.80271 15.1032C9.39179 15.7904 \
                9.68633 16.1341 10.0842 16.317C10.482 16.5 10.9346 16.5 11.8397 \
                16.5H12.1603C13.0654 16.5 13.518 16.5 13.9158 16.317C14.3137 16.1341 \
                14.6082 15.7904 15.1973 15.1032L15.8027 14.3968C16.3918 13.7096 \
                16.6863 13.3659 17.0842 13.183C17.482 13 17.9346 13 18.8397 13H22
                """, roundCaps: true),
            ]
        case .altArrowRight:
            return [.stroke("M9 5L15 12L9 19", roundCaps: true)]
        case .altArrowLeft:
            return [.stroke("M15 5L9 12L15 19", roundCaps: true)]
        case .altArrowDown:
            return [.stroke("M19 9L12 15L5 9", roundCaps: true)]
        case .close:
            return [
                .stroke("M5.172 5.172L10.828 10.828", roundCaps: true),
                .stroke("M10.828 5.172L5.172 10.828", roundCaps: true),
            ]
        case .infoCircle:
            // Solar InfoCircle Linear - circle + stem + filled dot
            return [
                .circleStroke(cx: 12, cy: 12, r: 10),
                .stroke("M12 17V11", roundCaps: true),
                .circleFill(cx: 12, cy: 8, r: 1),
            ]
        case .paperclip:
            return [
                .stroke("""
                M7.9175 17.8068L15.8084 10.2535C16.7558 9.34668 16.7558 7.87637 15.8084 \
                6.96951C14.861 6.06265 13.325 6.06265 12.3776 6.96951L4.54387 14.4681C2.74382 \
                16.1911 2.74382 18.9847 4.54387 20.7077C6.34391 22.4308 9.26237 22.4308 \
                11.0624 20.7077L19.0105 13.0997C21.6632 10.5605 21.6632 6.44362 19.0105 \
                3.90441C16.3578 1.3652 12.0569 1.3652 9.40419 3.90441L3 10.0346
                """, roundCaps: true),
            ]
        case .gallery:
            // Solar Gallery Linear
            return [
                .stroke("""
                M2 12C2 7.28595 2 4.92893 3.46447 3.46447C4.92893 2 7.28595 2 12 2C16.714 \
                2 19.0711 2 20.5355 3.46447C22 4.92893 22 7.28595 22 12C22 16.714 22 \
                19.0711 20.5355 20.5355C19.0711 22 16.714 22 12 22C7.28595 22 4.92893 22 \
                3.46447 20.5355C2 19.0711 2 16.714 2 12Z
                """),
                .circleStroke(cx: 16, cy: 8, r: 2),
                .stroke("""
                M2 12.5001L3.75159 10.9675C4.66286 10.1702 6.03628 10.2159 6.89249 \
                11.0721L11.1822 15.3618C11.8694 16.0491 12.9512 16.1428 13.7464 \
                15.5839L14.0446 15.3744C15.1888 14.5702 16.7369 14.6634 17.7765 \
                15.599L21 18.5001
                """, roundCaps: true),
            ]
        case .videoLibrary:
            // Solar VideoLibrary Linear
            return [
                .stroke("M19.5617 7C19.7904 5.69523 18.7863 4.5 17.4617 4.5H6.53788C5.21323 4.5 4.20922 5.69523 4.43784 7"),
                .stroke("""
                M17.4999 4.5C17.5283 4.24092 17.5425 4.11135 17.5427 4.00435C17.545 \
                2.98072 16.7739 2.12064 15.7561 2.01142C15.6497 2 15.5194 2 15.2588 \
                2H8.74099C8.48035 2 8.35002 2 8.24362 2.01142C7.22584 2.12064 6.45481 \
                2.98072 6.45704 4.00434C6.45727 4.11135 6.47146 4.2409 6.49983 4.5
                """),
                .stroke("""
                M14.5812 13.6159C15.1396 13.9621 15.1396 14.8582 14.5812 15.2044L11.2096 \
                17.2945C10.6669 17.6309 10 17.1931 10 16.5003L10 12.32C10 11.6273 10.6669 \
                11.1894 11.2096 11.5258L14.5812 13.6159Z
                """),
                .stroke("""
                M2.38351 13.793C1.93748 10.6294 1.71447 9.04765 2.66232 8.02383C3.61017 \
                7 5.29758 7 8.67239 7H15.3276C18.7024 7 20.3898 7 21.3377 8.02383C22.2855 \
                9.04765 22.0625 10.6294 21.6165 13.793L21.1935 16.793C20.8437 19.2739 \
                20.6689 20.5143 19.7717 21.2572C18.8745 22 17.5512 22 14.9046 22H9.09536C6.44881 \
                22 5.12553 22 4.22834 21.2572C3.33115 20.5143 3.15626 19.2739 2.80648 \
                16.793L2.38351 13.793Z
                """),
            ]
        case .pen:
            return [
                .stroke("""
                M14.3601 4.07866L15.2869 3.15178C16.8226 1.61607 19.3125 1.61607 \
                20.8482 3.15178C22.3839 4.68748 22.3839 7.17735 20.8482 8.71306L19.9213 \
                9.63993M14.3601 4.07866C14.3601 4.07866 14.4759 6.04828 16.2138 7.78618C17.9517 \
                9.52407 19.9213 9.63993 19.9213 9.63993M14.3601 4.07866L5.83882 12.5999C5.26166 \
                13.1771 4.97308 13.4656 4.7249 13.7838C4.43213 14.1592 4.18114 14.5653 \
                3.97634 14.995C3.80273 15.3593 3.67368 15.7465 3.41556 16.5208L2.32181 \
                19.8021M19.9213 9.63993L11.4001 18.1612C10.8229 18.7383 10.5344 19.0269 \
                10.2162 19.2751C9.84082 19.5679 9.43469 19.8189 9.00498 20.0237C8.6407 \
                20.1973 8.25352 20.3263 7.47918 20.5844L4.19792 21.6782M4.19792 21.6782L3.39584 \
                21.9456C3.01478 22.0726 2.59466 21.9734 2.31063 21.6894C2.0266 21.4053 \
                1.92743 20.9852 2.05445 20.6042L2.32181 19.8021M4.19792 21.6782L2.32181 19.8021
                """, roundCaps: true),
            ]
        case .closeCircle:
            return [
                .circleStroke(cx: 12, cy: 12, r: 10),
                .stroke("M14.5 9.50002L9.5 14.5M9.49998 9.5L14.5 14.5", roundCaps: true),
            ]
        case .playCircle:
            return [
                .circleStroke(cx: 12, cy: 12, r: 10),
                .stroke("""
                M15.4137 10.941C16.1954 11.4026 16.1954 12.5974 15.4137 13.059L10.6935 \
                15.8458C9.93371 16.2944 9 15.7105 9 14.7868L9 9.21316C9 8.28947 9.93371 \
                7.70561 10.6935 8.15419L15.4137 10.941Z
                """),
            ]
        case .document:
            return [
                .stroke("""
                M3 10C3 6.22876 3 4.34315 4.17157 3.17157C5.34315 2 7.22876 2 11 2H13C16.7712 \
                2 18.6569 2 19.8284 3.17157C21 4.34315 21 6.22876 21 10V14C21 17.7712 21 \
                19.6569 19.8284 20.8284C18.6569 22 16.7712 22 13 22H11C7.22876 22 5.34315 \
                22 4.17157 20.8284C3 19.6569 3 17.7712 3 14V10Z
                """),
                .stroke("M8 10H16", roundCaps: true),
                .stroke("M8 14H13", roundCaps: true),
            ]
        case .arrowUp:
            return [.stroke("M12 20L12 4M12 4L18 10M12 4L6 10", roundCaps: true)]
        case .smileCircle:
            // Solar Smile Circle Linear - same glyph as the dashboard composer.
            return [
                .circleStroke(cx: 12, cy: 12, r: 10),
                .circleFill(cx: 9, cy: 10, r: 1),
                .circleFill(cx: 15, cy: 10, r: 1),
                .stroke("M8.5 14.5c1.2 1.5 3 2.2 3.5 2.2s2.3-.7 3.5-2.2", roundCaps: true),
            ]
        }
    }
}

// MARK: - SVG path → SwiftUI Path (subset M/L/H/V/C/Z, absolute + relative)

private extension Path {
    init(svgPath d: String) {
        self.init()
        let tokens = Self.tokenize(d)
        var i = 0
        var command: Character = "M"
        var current = CGPoint.zero
        var start = CGPoint.zero

        func nextNumber() -> CGFloat {
            precondition(i < tokens.count)
            let v = CGFloat(Double(tokens[i]) ?? 0)
            i += 1
            return v
        }

        while i < tokens.count {
            let t = tokens[i]
            if let c = t.first, c.isLetter {
                command = c
                i += 1
            }

            switch command {
            case "M":
                current = CGPoint(x: nextNumber(), y: nextNumber())
                start = current
                move(to: current)
                command = "L"
            case "m":
                current = CGPoint(x: current.x + nextNumber(), y: current.y + nextNumber())
                start = current
                move(to: current)
                command = "l"
            case "L":
                current = CGPoint(x: nextNumber(), y: nextNumber())
                addLine(to: current)
            case "l":
                current = CGPoint(x: current.x + nextNumber(), y: current.y + nextNumber())
                addLine(to: current)
            case "H":
                current = CGPoint(x: nextNumber(), y: current.y)
                addLine(to: current)
            case "h":
                current = CGPoint(x: current.x + nextNumber(), y: current.y)
                addLine(to: current)
            case "V":
                current = CGPoint(x: current.x, y: nextNumber())
                addLine(to: current)
            case "v":
                current = CGPoint(x: current.x, y: current.y + nextNumber())
                addLine(to: current)
            case "C":
                let c1 = CGPoint(x: nextNumber(), y: nextNumber())
                let c2 = CGPoint(x: nextNumber(), y: nextNumber())
                current = CGPoint(x: nextNumber(), y: nextNumber())
                addCurve(to: current, control1: c1, control2: c2)
            case "c":
                let c1 = CGPoint(x: current.x + nextNumber(), y: current.y + nextNumber())
                let c2 = CGPoint(x: current.x + nextNumber(), y: current.y + nextNumber())
                current = CGPoint(x: current.x + nextNumber(), y: current.y + nextNumber())
                addCurve(to: current, control1: c1, control2: c2)
            case "Z", "z":
                closeSubpath()
                current = start
            default:
                i += 1
            }
        }
    }

    static func tokenize(_ d: String) -> [String] {
        var tokens: [String] = []
        var number = ""
        func flushNumber() {
            if !number.isEmpty {
                tokens.append(number)
                number = ""
            }
        }
        for ch in d {
            if ch.isLetter {
                flushNumber()
                tokens.append(String(ch))
            } else if ch == "," || ch.isWhitespace {
                flushNumber()
            } else if ch == "-" || ch == "+" {
                if number.isEmpty || number.last == "e" || number.last == "E" {
                    number.append(ch)
                } else {
                    flushNumber()
                    number.append(ch)
                }
            } else {
                number.append(ch)
            }
        }
        flushNumber()
        return tokens
    }
}
