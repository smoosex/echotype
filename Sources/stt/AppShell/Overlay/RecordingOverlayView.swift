import SwiftUI

struct RecordingOverlayView: View {
    @ObservedObject var levelStore: RecordingOverlayLevelStore

    private let barWeights: [CGFloat] = [0.45, 0.62, 0.82, 1.0, 0.82, 0.62, 0.45]
    private let contentHeight: CGFloat = 18

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1.0 / 30.0)) { context in
            let timeline = context.date.timeIntervalSinceReferenceDate
            let widthProgress = horizontalProgress
            let heightProgress = verticalProgress
            let baseVisibilityProgress = baseProgress
            let level = smoothedLevel
            let notchWidth = RecordingOverlayMetrics.resolvedNotchWidth(levelStore.notchWidth)
            let notchHeight = RecordingOverlayMetrics.resolvedNotchHeight(levelStore.notchHeight)
            let finalWidth = RecordingOverlayMetrics.finalWidth(notchWidth: notchWidth)
            let finalHeight = RecordingOverlayMetrics.finalHeight(notchHeight: notchHeight)
            let currentWidth = RecordingOverlayMetrics.panelWidth(
                baseVisibilityProgress: baseVisibilityProgress,
                widthProgress: widthProgress,
                notchWidth: notchWidth
            )
            let currentHeight = RecordingOverlayMetrics.panelHeight(
                baseVisibilityProgress: baseVisibilityProgress,
                heightProgress: heightProgress,
                notchHeight: notchHeight
            )
            let notchMaskWidth = RecordingOverlayMetrics.notchMaskWidth(
                baseVisibilityProgress: baseVisibilityProgress,
                notchWidth: notchWidth
            )
            let notchMaskHeight = RecordingOverlayMetrics.notchMaskHeight(
                baseVisibilityProgress: baseVisibilityProgress,
                heightProgress: heightProgress,
                notchHeight: notchHeight,
                panelHeight: currentHeight
            )
            let contentTop = RecordingOverlayMetrics.contentTopInset(
                currentHeight: currentHeight,
                notchHeight: notchHeight,
                contentHeight: contentHeight
            )
            let contentVisibility = RecordingOverlayMetrics.contentVisibility(
                widthProgress: widthProgress,
                heightProgress: heightProgress,
                currentHeight: currentHeight,
                notchHeight: notchHeight,
                contentHeight: contentHeight
            )

            ZStack(alignment: .top) {
                RecordingOverlayNotchShape(
                    topCornerRadius: RecordingOverlayMetrics.topCornerRadius,
                    bottomCornerRadius: RecordingOverlayMetrics.bottomCornerRadius
                )
                .fill(Color.black)
                .frame(width: currentWidth, height: currentHeight)

                Rectangle()
                    .fill(Color.black)
                    .frame(
                        width: max(currentWidth - RecordingOverlayMetrics.topCornerRadius * 2, 0),
                        height: currentHeight > 0 ? 1 : 0
                    )

                Rectangle()
                    .fill(Color.black)
                    .frame(width: notchMaskWidth, height: notchMaskHeight)
                    .mask(
                        RecordingOverlayNotchShape(
                            topCornerRadius: RecordingOverlayMetrics.topCornerRadius,
                            bottomCornerRadius: RecordingOverlayMetrics.notchBottomCornerRadius
                        )
                    )
                    .frame(width: finalWidth, height: finalHeight, alignment: .top)

                HStack(spacing: 12) {
                    Image(systemName: "mic.fill")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Color.white)
                        .frame(width: 16, height: 16)

                    HStack(alignment: .center, spacing: 4) {
                        ForEach(Array(barWeights.enumerated()), id: \.offset) { index, weight in
                            RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                                .fill(barColor)
                                .frame(
                                    width: 4,
                                    height: barHeight(
                                        weight: weight,
                                        level: level,
                                        timeline: timeline,
                                        index: index,
                                        visibility: contentVisibility
                                    )
                                )
                        }
                    }
                    .frame(height: 18)
                }
                .frame(
                    width: max(currentWidth - 32, 1),
                    height: contentHeight,
                    alignment: .center
                )
                .offset(y: contentTop)
                .opacity(contentVisibility)
            }
            .frame(width: finalWidth, height: finalHeight, alignment: .top)
        }
        .frame(
            width: RecordingOverlayMetrics.finalWidth(
                notchWidth: RecordingOverlayMetrics.resolvedNotchWidth(levelStore.notchWidth)
            ),
            height: RecordingOverlayMetrics.finalHeight(
                notchHeight: RecordingOverlayMetrics.resolvedNotchHeight(levelStore.notchHeight)
            ),
            alignment: .top
        )
        .ignoresSafeArea(.all, edges: .top)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private var horizontalProgress: CGFloat {
        max(0, min(1, levelStore.widthProgress))
    }

    private var verticalProgress: CGFloat {
        max(0, min(1, levelStore.heightProgress))
    }

    private var baseProgress: CGFloat {
        max(0, min(1, levelStore.baseVisibilityProgress))
    }

    private var smoothedLevel: CGFloat {
        let clamped = min(max(levelStore.level, 0), 1)
        return pow(CGFloat(clamped), 0.82)
    }

    private var barColor: Color {
        Color(red: 0.46, green: 0.73, blue: 0.98)
    }

    private func barHeight(
        weight: CGFloat,
        level: CGFloat,
        timeline: TimeInterval,
        index: Int,
        visibility: CGFloat
    ) -> CGFloat {
        let baseHeight: CGFloat = 4
        let activeRange: CGFloat = 14
        let pulse = sin((timeline * 8.2) + Double(index) * 0.82)
        let microMotion = CGFloat((pulse + 1) * 0.5) * (0.75 + level * 1.6)
        let amplitude = activeRange * weight * max(level, 0.08)
        let height = (baseHeight + amplitude + microMotion) * visibility
        return min(18, max(baseHeight * visibility, height))
    }
}

enum RecordingOverlayMetrics {
    static let fallbackNotchWidth: CGFloat = 172.5
    static let fallbackNotchHeight: CGFloat = 37
    static let horizontalExpansion: CGFloat = 12
    static let minimumHeight: CGFloat = 70
    static let extraHeight: CGFloat = 33
    static let topCornerRadius: CGFloat = 6
    static let bottomCornerRadius: CGFloat = 18
    static let notchBottomCornerRadius: CGFloat = 14
    static let contentTopSpacing: CGFloat = 4
    static let contentBottomInset: CGFloat = 6
    static let contentRevealProgressThreshold: CGFloat = 0.08

    static func resolvedNotchWidth(_ width: CGFloat) -> CGFloat {
        width > 0 ? width : fallbackNotchWidth
    }

    static func resolvedNotchHeight(_ height: CGFloat) -> CGFloat {
        height > 0 ? height : fallbackNotchHeight
    }

    static func finalWidth(notchWidth: CGFloat) -> CGFloat {
        notchWidth + horizontalExpansion
    }

    static func finalHeight(notchHeight: CGFloat) -> CGFloat {
        max(minimumHeight, notchHeight + extraHeight)
    }

    static func easedProgress(_ progress: CGFloat) -> CGFloat {
        let value = max(0, min(1, progress))
        let inverse = 1 - value
        return 1 - inverse * inverse * inverse
    }

    static func panelWidth(baseVisibilityProgress: CGFloat, widthProgress: CGFloat, notchWidth: CGFloat) -> CGFloat {
        let baseProgress = easedProgress(baseVisibilityProgress)
        let progress = easedProgress(widthProgress)
        guard baseProgress > 0 else { return 0 }
        return notchWidth * baseProgress + horizontalExpansion * progress
    }

    static func panelHeight(baseVisibilityProgress: CGFloat, heightProgress: CGFloat, notchHeight: CGFloat) -> CGFloat {
        let baseProgress = easedProgress(baseVisibilityProgress)
        let progress = easedProgress(heightProgress)
        guard baseProgress > 0 else { return 0 }
        return notchHeight * baseProgress + max(finalHeight(notchHeight: notchHeight) - notchHeight, 0) * progress
    }

    static func notchMaskWidth(baseVisibilityProgress: CGFloat, notchWidth: CGFloat) -> CGFloat {
        let baseProgress = easedProgress(baseVisibilityProgress)
        guard baseProgress > 0 else { return 0 }
        return notchWidth * baseProgress
    }

    static func notchMaskHeight(
        baseVisibilityProgress: CGFloat,
        heightProgress: CGFloat,
        notchHeight: CGFloat,
        panelHeight: CGFloat
    ) -> CGFloat {
        let baseProgress = easedProgress(baseVisibilityProgress)
        let progress = easedProgress(heightProgress)
        guard baseProgress > 0 || progress > 0 else { return 0 }
        return min(panelHeight, notchHeight * baseProgress)
    }

    static func contentTopInset(
        currentHeight: CGFloat,
        notchHeight: CGFloat,
        contentHeight: CGFloat
    ) -> CGFloat {
        let desiredTop = notchHeight + contentTopSpacing
        let maxTop = max(0, currentHeight - contentBottomInset - contentHeight)
        return min(desiredTop, maxTop)
    }

    static func contentVisibility(
        widthProgress: CGFloat,
        heightProgress: CGFloat,
        currentHeight: CGFloat,
        notchHeight: CGFloat,
        contentHeight: CGFloat
    ) -> CGFloat {
        let widthVisibility = easedProgress(widthProgress)
        let heightVisibility = easedProgress(heightProgress)
        let progressVisibility = max(
            0,
            min(1, (min(widthVisibility, heightVisibility) - contentRevealProgressThreshold) / 0.12)
        )
        let availableHeight = currentHeight - contentBottomInset - (notchHeight + contentTopSpacing)
        let spaceVisibility = max(0, min(1, (availableHeight - contentHeight) / 4))
        return min(progressVisibility, spaceVisibility)
    }
}

private struct RecordingOverlayNotchShape: Shape {
    private var topCornerRadius: CGFloat
    private var bottomCornerRadius: CGFloat

    init(topCornerRadius: CGFloat, bottomCornerRadius: CGFloat) {
        self.topCornerRadius = topCornerRadius
        self.bottomCornerRadius = bottomCornerRadius
    }

    var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { .init(topCornerRadius, bottomCornerRadius) }
        set {
            topCornerRadius = newValue.first
            bottomCornerRadius = newValue.second
        }
    }

    func path(in rect: CGRect) -> Path {
        guard rect.width > 0.1, rect.height > 0.1 else {
            return Path()
        }

        let topRadius = min(topCornerRadius, rect.width / 2, rect.height / 2)
        let bottomRadius = min(bottomCornerRadius, rect.width / 2, rect.height / 2)
        var path = Path()

        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addQuadCurve(
            to: CGPoint(x: rect.minX + topRadius, y: rect.minY + topRadius),
            control: CGPoint(x: rect.minX + topRadius, y: rect.minY)
        )
        path.addLine(to: CGPoint(x: rect.minX + topRadius, y: rect.maxY - bottomRadius))
        path.addQuadCurve(
            to: CGPoint(x: rect.minX + topRadius + bottomRadius, y: rect.maxY),
            control: CGPoint(x: rect.minX + topRadius, y: rect.maxY)
        )
        path.addLine(to: CGPoint(x: rect.maxX - topRadius - bottomRadius, y: rect.maxY))
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX - topRadius, y: rect.maxY - bottomRadius),
            control: CGPoint(x: rect.maxX - topRadius, y: rect.maxY)
        )
        path.addLine(to: CGPoint(x: rect.maxX - topRadius, y: rect.minY + topRadius))
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX, y: rect.minY),
            control: CGPoint(x: rect.maxX - topRadius, y: rect.minY)
        )
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY))

        return path
    }
}

enum RecordingOverlayPresentationPhase {
    case hidden
    case appearing
    case visible
    case disappearing
}

@MainActor
final class RecordingOverlayLevelStore: ObservableObject {
    @Published var level: Double = 0
    @Published var baseVisibilityProgress: CGFloat = 0
    @Published var widthProgress: CGFloat = 0
    @Published var heightProgress: CGFloat = 0
    @Published var presentationPhase: RecordingOverlayPresentationPhase = .hidden
    @Published var notchWidth: CGFloat = RecordingOverlayMetrics.fallbackNotchWidth
    @Published var notchHeight: CGFloat = RecordingOverlayMetrics.fallbackNotchHeight
}
