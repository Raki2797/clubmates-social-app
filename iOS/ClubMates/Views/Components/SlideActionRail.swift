import SwiftUI

struct SlideActionRail: View {
    let onPass: () -> Void
    let onLike: () -> Void
    let onGift: () -> Void

    @State private var thumbOffset: CGFloat = 0
    @State private var hasCommitted: Bool = false

    private let trackHeight: CGFloat = 56
    private let thumbSize: CGFloat = 48
    private let commitFraction: CGFloat = 0.65

    var body: some View {
        GeometryReader { geo in
            let halfTrack = (geo.size.width - thumbSize) / 2
            let progress = thumbOffset / halfTrack
            let absProgress = min(abs(progress), 1.0)

            ZStack {
                Capsule()
                    .fill(AppTheme.surface)

                // Directional color fill
                Capsule()
                    .fill(
                        progress < 0
                            ? Color(hex: "FF4757").opacity(Double(absProgress * 0.35))
                            : Color(hex: "00E5A0").opacity(Double(absProgress * 0.35))
                    )

                HStack {
                    // Left endpoint icon (Pass)
                    Image(systemName: "xmark")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundColor(Color(hex: "FF4757"))
                        .opacity(progress < 0 ? Double(absProgress) : 0)
                        .padding(.leading, 18)

                    Spacer()

                    // Right endpoint icon (Like)
                    Image(systemName: "heart.fill")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundColor(Color(hex: "00E5A0"))
                        .opacity(progress > 0 ? Double(absProgress) : 0)
                        .padding(.trailing, 18)
                }

                // Draggable thumb
                Circle()
                    .fill(AppTheme.surfaceElevated)
                    .frame(width: thumbSize, height: thumbSize)
                    .overlay(
                        Circle()
                            .stroke(Color.white.opacity(0.12), lineWidth: 1)
                    )
                    .overlay(
                        Group {
                            if absProgress < 0.3 {
                                Image(systemName: "gift.fill")
                                    .font(.system(size: 16, weight: .semibold))
                                    .foregroundColor(AppTheme.gold)
                                    .opacity(1.0 - Double(absProgress / 0.3))
                            } else if progress < 0 {
                                Image(systemName: "xmark")
                                    .font(.system(size: 16, weight: .bold))
                                    .foregroundColor(Color(hex: "FF4757"))
                            } else {
                                Image(systemName: "heart.fill")
                                    .font(.system(size: 16, weight: .bold))
                                    .foregroundColor(Color(hex: "00E5A0"))
                            }
                        }
                    )
                    .shadow(color: .black.opacity(0.2), radius: 8, x: 0, y: 4)
                    .offset(x: thumbOffset)
                    .onTapGesture { onGift() }
                    .gesture(
                        DragGesture(minimumDistance: 8)
                            .onChanged { value in
                                guard !hasCommitted else { return }
                                let clamped = max(-halfTrack, min(halfTrack, value.translation.width))
                                thumbOffset = clamped

                                if abs(clamped) >= halfTrack * commitFraction {
                                    hasCommitted = true
                                    let generator = UIImpactFeedbackGenerator(style: .medium)
                                    generator.impactOccurred()

                                    if clamped < 0 {
                                        onPass()
                                    } else {
                                        onLike()
                                    }

                                    withAnimation(.spring(response: 0.45, dampingFraction: 0.7)) {
                                        thumbOffset = 0
                                    }
                                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                                        hasCommitted = false
                                    }
                                }
                            }
                            .onEnded { _ in
                                if !hasCommitted {
                                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                        thumbOffset = 0
                                    }
                                }
                            }
                    )
            }
            .frame(height: trackHeight)
            .frame(maxWidth: .infinity)
        }
        .frame(height: trackHeight)
    }
}
