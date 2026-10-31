import SwiftUI

private enum SkeletonPalette {
    static let blockFill = LinearGradient(
        colors: [
            Color(hex: "4F4963"),
            Color(hex: "6D6487"),
            Color(hex: "57506C")
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    static let cardFill = LinearGradient(
        colors: [
            Color(hex: "39334A"),
            Color(hex: "544C6A"),
            Color(hex: "40384F")
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    static let edgeStroke = LinearGradient(
        colors: [
            Color.white.opacity(0.12),
            Color(hex: "FFD8EC").opacity(0.10),
            Color.white.opacity(0.05)
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
}

private struct ShimmerStripe: View {
    let phase: CGFloat

    var body: some View {
        GeometryReader { geo in
            let stripeWidth = max(geo.size.width * 0.7, 88)
            let travel = geo.size.width + (stripeWidth * 2)

            LinearGradient(
                colors: [
                    Color.white.opacity(0.0),
                    Color(hex: "FFD8EC").opacity(0.11),
                    Color(hex: "FFF4FB").opacity(0.42),
                    Color(hex: "DCCBFF").opacity(0.16),
                    Color.white.opacity(0.0)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(width: stripeWidth, height: max(geo.size.height * 1.8, 72))
            .rotationEffect(.degrees(18))
            .offset(
                x: -stripeWidth + (travel * phase),
                y: -geo.size.height * 0.35
            )
        }
        .blendMode(.screen)
        .allowsHitTesting(false)
    }
}

private struct SkeletonBlock: View {
    let cornerRadius: CGFloat
    let phase: CGFloat
    var fill: LinearGradient = SkeletonPalette.blockFill

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)

        shape
            .fill(fill)
            .overlay {
                ShimmerStripe(phase: phase)
                    .mask(shape)
            }
            .overlay {
                shape.stroke(SkeletonPalette.edgeStroke, lineWidth: 1)
            }
    }
}

private struct SkeletonCircle: View {
    let phase: CGFloat

    var body: some View {
        let shape = Circle()

        shape
            .fill(SkeletonPalette.blockFill)
            .overlay {
                ShimmerStripe(phase: phase)
                    .mask(shape)
            }
            .overlay {
                shape.stroke(SkeletonPalette.edgeStroke, lineWidth: 1)
            }
    }
}

struct ProfileShimmerView: View {
    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 45.0)) { context in
            let phase = shimmerPhase(at: context.date)

            ScrollView(showsIndicators: false) {
                VStack(spacing: 0) {
                    headerSkeleton(phase: phase)
                    statsSkeleton(phase: phase)
                        .padding(.top, 20)
                        .padding(.horizontal, 20)
                    bioSkeleton(phase: phase)
                        .padding(.top, 24)
                        .padding(.horizontal, 20)
                    photosSkeleton(phase: phase)
                        .padding(.top, 24)
                    promptsSkeleton(phase: phase)
                        .padding(.top, 24)
                        .padding(.horizontal, 20)
                }
                .padding(.bottom, 40)
            }
        }
    }

    private func shimmerPhase(at date: Date) -> CGFloat {
        let duration = 1.15
        let progress = date.timeIntervalSinceReferenceDate
            .truncatingRemainder(dividingBy: duration) / duration
        return CGFloat(progress)
    }

    private func headerSkeleton(phase: CGFloat) -> some View {
        VStack(spacing: 0) {
            SkeletonCircle(phase: phase)
                .frame(width: 96, height: 96)
                .padding(.top, 52)
                .padding(.bottom, 16)

            SkeletonBlock(cornerRadius: 8, phase: phase)
                .frame(width: 160, height: 24)

            SkeletonBlock(cornerRadius: 6, phase: phase)
                .frame(width: 100, height: 14)
                .padding(.top, 8)

            SkeletonBlock(cornerRadius: 20, phase: phase, fill: SkeletonPalette.cardFill)
                .frame(width: 120, height: 36)
                .padding(.top, 14)
                .padding(.bottom, 28)
        }
        .frame(maxWidth: .infinity)
        .background(
            LinearGradient(
                colors: [Color(hex: "21172F"), Color(hex: "39234E"), Color(hex: "17151D")],
                startPoint: .top,
                endPoint: .bottom
            )
        )
    }

    private func statsSkeleton(phase: CGFloat) -> some View {
        HStack(spacing: 10) {
            ForEach(0..<3, id: \.self) { _ in
                SkeletonBlock(cornerRadius: 16, phase: phase, fill: SkeletonPalette.cardFill)
                    .frame(maxWidth: .infinity)
                    .frame(height: 90)
            }
        }
    }

    private func bioSkeleton(phase: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            SkeletonBlock(cornerRadius: 6, phase: phase)
                .frame(width: 60, height: 14)

            VStack(spacing: 8) {
                ForEach([1.0, 0.85, 0.6], id: \.self) { width in
                    SkeletonBlock(cornerRadius: 5, phase: phase)
                        .frame(maxWidth: .infinity)
                        .frame(height: 12)
                        .scaleEffect(x: width, anchor: .leading)
                }
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            SkeletonBlock(cornerRadius: 18, phase: phase, fill: SkeletonPalette.cardFill)
        }
    }

    private func photosSkeleton(phase: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            SkeletonBlock(cornerRadius: 6, phase: phase)
                .frame(width: 80, height: 14)
                .padding(.horizontal, 20)

            HStack(alignment: .top, spacing: 8) {
                VStack(spacing: 8) {
                    SkeletonBlock(cornerRadius: 18, phase: phase, fill: SkeletonPalette.cardFill)
                        .frame(maxWidth: .infinity)
                        .frame(height: 200)

                    SkeletonBlock(cornerRadius: 18, phase: phase, fill: SkeletonPalette.cardFill)
                        .frame(maxWidth: .infinity)
                        .frame(height: 140)
                }

                VStack(spacing: 8) {
                    SkeletonBlock(cornerRadius: 18, phase: phase, fill: SkeletonPalette.cardFill)
                        .frame(maxWidth: .infinity)
                        .frame(height: 140)

                    SkeletonBlock(cornerRadius: 18, phase: phase, fill: SkeletonPalette.cardFill)
                        .frame(maxWidth: .infinity)
                        .frame(height: 200)
                }
            }
            .padding(.horizontal, 20)
        }
    }

    private func promptsSkeleton(phase: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            SkeletonBlock(cornerRadius: 6, phase: phase)
                .frame(width: 120, height: 14)

            ForEach(0..<2, id: \.self) { _ in
                SkeletonBlock(cornerRadius: 18, phase: phase, fill: SkeletonPalette.cardFill)
                    .frame(maxWidth: .infinity)
                    .frame(height: 90)
            }
        }
    }
}
