import SwiftUI
import UIKit

enum CropAspectRatio: String, CaseIterable {
    case portrait = "3:4"
    case square   = "1:1"
    case free     = "Free"
}

// MARK: - Gesture State (isolated from main view to prevent full-body re-evaluation)

@Observable
private final class CropGestureState {
    var scale: CGFloat = 1.0
    var lastScale: CGFloat = 1.0
    var offset: CGSize = .zero
    var lastOffset: CGSize = .zero
    var showGrid = false

    func reset() {
        scale = 1; lastScale = 1; offset = .zero; lastOffset = .zero
    }
}

// MARK: - PhotoCropView

struct PhotoCropView: View {
    let images: [UIImage]
    let onComplete: ([Data]) -> Void
    let onCancel: () -> Void

    @State private var currentIndex   = 0
    @State private var aspectRatio    = CropAspectRatio.portrait
    @State private var rotationTurns  = 0
    @State private var croppedResults: [Data] = []
    @State private var containerSize: CGSize = .zero
    @State private var cropSize: CGSize = .zero
    @State private var cropSizeAtDragStart: CGSize = .zero
    @State private var isDraggingCorner = false

    @State private var gestureState = CropGestureState()
    @State private var displayImage: UIImage = UIImage()
    @State private var fullResImage: UIImage = UIImage()

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                topBar

                GeometryReader { canvasGeo in
                    let sz = canvasGeo.size
                    ZStack {
                        CropImageCanvas(
                            image: displayImage,
                            containerSize: sz,
                            cropSize: cropSize,
                            gestureState: gestureState,
                            isDraggingCorner: $isDraggingCorner
                        )

                        if cropSize != .zero {
                            CropDimmingShape(cropSize: cropSize)
                                .fill(Color.black.opacity(0.6), style: FillStyle(eoFill: true))
                                .allowsHitTesting(false)

                            CropOverlayView(cropSize: cropSize, showGrid: gestureState.showGrid)
                                .allowsHitTesting(false)

                            cornerGestureAreas(containerSize: sz)
                        }
                    }
                    .clipped()
                    .onAppear { updateCanvasLayout(sz, reset: false) }
                    .onChange(of: sz) { _, newSz in updateCanvasLayout(newSz, reset: true) }
                }

                bottomPanel
            }
            .background(AppTheme.background.ignoresSafeArea())
            .navigationBarHidden(true)
            .toolbarVisibility(.hidden, for: .navigationBar)
        }
        .onAppear { prepareImages() }
        .onChange(of: currentIndex) { _, _ in
            rotationTurns = 0
            prepareImages()
            gestureState.reset()
        }
        .onChange(of: rotationTurns) { _, _ in
            prepareImages()
            gestureState.reset()
        }
        .onChange(of: aspectRatio) { _, newRatio in
            var transaction = Transaction()
            transaction.animation = .spring(response: 0.28, dampingFraction: 0.8)
            withTransaction(transaction) {
                cropSize = defaultCropSize(in: containerSize, ratio: newRatio)
                gestureState.reset()
            }
        }
    }

    // MARK: - Top Bar

    private var topBar: some View {
        HStack(alignment: .center) {
            Button("Cancel", action: onCancel)
                .font(.system(size: 16, weight: .medium, design: .rounded))
                .foregroundColor(.white)

            Spacer()

            if images.count > 1 {
                HStack(spacing: 6) {
                    ForEach(0..<images.count, id: \.self) { i in
                        Circle()
                            .fill(i == currentIndex ? Color.white : Color.white.opacity(0.3))
                            .frame(width: 6, height: 6)
                    }
                }
            }

            Spacer()

            Button {
                rotationTurns = (rotationTurns + 1) % 4
            } label: {
                Image(systemName: "rotate.right")
                    .font(.system(size: 20, weight: .medium))
                    .foregroundColor(.white)
                    .frame(width: 44, height: 44)
            }
        }
        .padding(.horizontal, 20)
        .frame(height: 52)
    }

    // MARK: - Corner Gesture Areas

    private func cornerGestureAreas(containerSize: CGSize) -> some View {
        let cx = containerSize.width / 2
        let cy = containerSize.height / 2
        let hw = cropSize.width / 2
        let hh = cropSize.height / 2
        let hit: CGFloat = 52

        return ZStack {
            ForEach(CropCorner.allCases, id: \.self) { c in
                Color.clear
                    .frame(width: hit, height: hit)
                    .contentShape(Rectangle())
                    .position(x: cx + c.xSign * hw, y: cy + c.ySign * hh)
                    .gesture(
                        DragGesture(minimumDistance: 1)
                            .onChanged { v in
                                if !isDraggingCorner {
                                    isDraggingCorner = true
                                    cropSizeAtDragStart = cropSize
                                }
                                gestureState.showGrid = true
                                applyCornerDrag(corner: c, t: v.translation, cs: containerSize)
                            }
                            .onEnded { _ in
                                isDraggingCorner = false
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                                    if !isDraggingCorner { gestureState.showGrid = false }
                                }
                            }
                    )
            }
        }
    }

    private func applyCornerDrag(corner: CropCorner, t: CGSize, cs: CGSize) {
        let startHW = cropSizeAtDragStart.width / 2
        let startHH = cropSizeAtDragStart.height / 2
        let minSide: CGFloat = 80
        let maxW = cs.width - 24
        let maxH = cs.height - 24

        switch aspectRatio {
        case .portrait, .square:
            let startDist = sqrt(startHW * startHW + startHH * startHH)
            guard startDist > 0 else { return }
            let nx = corner.xSign * startHW + t.width
            let ny = corner.ySign * startHH + t.height
            let newDist = sqrt(nx * nx + ny * ny)
            let s = newDist / startDist
            let r: CGFloat = aspectRatio == .portrait ? 3.0 / 4.0 : 1.0
            let newW = min(max(cropSizeAtDragStart.width * s, minSide), maxW)
            let newH = newW / r
            if newH >= minSide && newH <= maxH {
                cropSize = CGSize(width: newW, height: newH)
            }
        case .free:
            let newHW = max(minSide / 2, abs(corner.xSign * startHW + t.width))
            let newHH = max(minSide / 2, abs(corner.ySign * startHH + t.height))
            cropSize = CGSize(width: min(newHW * 2, maxW), height: min(newHH * 2, maxH))
        }

        let fill = imageFillSize(in: cs)
        let maxX = max(0, (fill.width * gestureState.scale - cropSize.width) / 2)
        let maxY = max(0, (fill.height * gestureState.scale - cropSize.height) / 2)
        let clamped = CGSize(
            width: min(max(gestureState.offset.width, -maxX), maxX),
            height: min(max(gestureState.offset.height, -maxY), maxY)
        )
        gestureState.offset = clamped
        gestureState.lastOffset = clamped
    }

    // MARK: - Bottom Panel

    private var bottomPanel: some View {
        VStack(spacing: 16) {
            if images.count > 1 { filmstrip }
            aspectRatioChips
            actionRow
        }
        .padding(.top, 20)
        .padding(.horizontal, 24)
        .background(
            UnevenRoundedRectangle(topLeadingRadius: 28, bottomLeadingRadius: 0, bottomTrailingRadius: 0, topTrailingRadius: 28)
                .fill(AppTheme.cardBackground)
                .overlay(alignment: .top) {
                    Rectangle()
                        .fill(Color.white.opacity(0.06))
                        .frame(height: 1)
                }
                .ignoresSafeArea(edges: .bottom)
        )
        .safeAreaPadding(.bottom)
    }

    // MARK: - Filmstrip

    private var filmstrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(0..<images.count, id: \.self) { i in
                    Button { currentIndex = i } label: {
                        ZStack(alignment: .bottomTrailing) {
                            Image(uiImage: images[i])
                                .resizable()
                                .scaledToFill()
                                .frame(width: 48, height: 48)
                                .clipped()
                                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                                        .stroke(
                                            i == currentIndex ? Color.white : Color.white.opacity(0.15),
                                            lineWidth: i == currentIndex ? 2.5 : 1
                                        )
                                )

                            if i < croppedResults.count {
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.system(size: 12, weight: .bold))
                                    .foregroundStyle(.white)
                                    .background(
                                        Circle()
                                            .fill(AppTheme.primaryGradient)
                                            .frame(width: 16, height: 16)
                                    )
                                    .offset(x: -3, y: -3)
                            }
                        }
                        .frame(width: 48, height: 48)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    // MARK: - Aspect Ratio Chips

    private var aspectRatioChips: some View {
        HStack(spacing: 8) {
            ForEach(CropAspectRatio.allCases, id: \.self) { ratio in
                Button { aspectRatio = ratio } label: {
                    HStack(spacing: 6) {
                        ratioIcon(ratio)
                        Text(ratio.rawValue)
                            .font(.system(size: 13, weight: .semibold, design: .rounded))
                    }
                    .foregroundColor(aspectRatio == ratio ? .white : AppTheme.textSecondary)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(
                        Capsule()
                            .fill(aspectRatio == ratio ? AnyShapeStyle(AppTheme.primaryGradient) : AnyShapeStyle(AppTheme.surface))
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }

    @ViewBuilder
    private func ratioIcon(_ ratio: CropAspectRatio) -> some View {
        let active = aspectRatio == ratio
        switch ratio {
        case .portrait:
            RoundedRectangle(cornerRadius: 1.5)
                .stroke(active ? Color.white : AppTheme.textSecondary, lineWidth: 1.4)
                .frame(width: 10, height: 14)
        case .square:
            RoundedRectangle(cornerRadius: 1.5)
                .stroke(active ? Color.white : AppTheme.textSecondary, lineWidth: 1.4)
                .frame(width: 12, height: 12)
        case .free:
            Image(systemName: "crop")
                .font(.system(size: 13, weight: .medium))
        }
    }

    // MARK: - Action Row

    private var actionRow: some View {
        HStack {
            if currentIndex > 0 {
                Button {
                    croppedResults.removeLast()
                    currentIndex -= 1
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 12, weight: .semibold))
                        Text("Back")
                            .font(.system(size: 15, weight: .medium, design: .rounded))
                    }
                    .foregroundColor(.white.opacity(0.7))
                }
            }

            Spacer()

            Button(action: useCurrentPhoto) {
                Text(currentIndex == images.count - 1
                     ? (images.count > 1 ? "Use Photos" : "Use Photo")
                     : "Next")
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                    .padding(.horizontal, 36)
                    .padding(.vertical, 14)
                    .background(AppTheme.primaryGradient)
                    .clipShape(Capsule())
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Helpers

    private func imageFillSize(in size: CGSize) -> CGSize {
        let imgW = displayImage.size.width
        let imgH = displayImage.size.height
        guard imgW > 0, imgH > 0 else { return size }
        let targetW = cropSize.width > 0 ? cropSize.width : size.width
        let targetH = cropSize.height > 0 ? cropSize.height : size.height
        let baseScale = max(targetW / imgW, targetH / imgH)
        return CGSize(width: imgW * baseScale, height: imgH * baseScale)
    }

    private func defaultCropSize(in size: CGSize, ratio: CropAspectRatio) -> CGSize {
        guard size.width > 0 else { return CGSize(width: 300, height: 400) }
        let maxW = size.width - 32
        let maxH = size.height - 32
        switch ratio {
        case .portrait:
            let w = min(maxW, maxH * 0.75)
            return CGSize(width: w, height: w / 0.75)
        case .square:
            let s = min(maxW, maxH)
            return CGSize(width: s, height: s)
        case .free:
            return CGSize(width: maxW, height: maxH)
        }
    }

    private func updateCanvasLayout(_ size: CGSize, reset: Bool) {
        guard size.width > 0, size.height > 0 else { return }
        let widthChanged = abs(containerSize.width - size.width) > 0.5
        let heightChanged = abs(containerSize.height - size.height) > 0.5
        guard widthChanged || heightChanged || cropSize == .zero else { return }

        containerSize = size
        cropSize = defaultCropSize(in: size, ratio: aspectRatio)
        if reset { gestureState.reset() }
    }

    private func prepareImages() {
        guard images.indices.contains(currentIndex) else {
            displayImage = UIImage()
            fullResImage = UIImage()
            return
        }
        let rotated = rotatedImage(images[currentIndex], turns: rotationTurns)
        fullResImage = rotated
        displayImage = downsampledImage(rotated, maxDimension: 1200)
    }

    private func useCurrentPhoto() {
        if let data = cropData() {
            croppedResults.append(data)
        }
        if currentIndex < images.count - 1 {
            currentIndex += 1
        } else {
            onComplete(croppedResults)
        }
    }

    private func cropData() -> Data? {
        let image = fullResImage
        let imgSize = image.size
        guard imgSize.width > 0, imgSize.height > 0, containerSize.width > 0 else { return nil }
        let scale = gestureState.scale
        let offset = gestureState.offset
        let baseScale = max(cropSize.width / imgSize.width, cropSize.height / imgSize.height)
        let totalScale = baseScale * scale
        let imageCenterX = containerSize.width / 2 + offset.width
        let imageCenterY = containerSize.height / 2 + offset.height
        let scaledW = imgSize.width * totalScale
        let scaledH = imgSize.height * totalScale
        let cropMinX = (containerSize.width - cropSize.width) / 2
        let cropMinY = (containerSize.height - cropSize.height) / 2
        let rawX = (cropMinX - (imageCenterX - scaledW / 2)) / totalScale
        let rawY = (cropMinY - (imageCenterY - scaledH / 2)) / totalScale
        let rawW = cropSize.width / totalScale
        let rawH = cropSize.height / totalScale
        let clampX = max(0, min(rawX, imgSize.width))
        let clampY = max(0, min(rawY, imgSize.height))
        let clampW = min(rawW, imgSize.width - clampX)
        let clampH = min(rawH, imgSize.height - clampY)
        guard clampW > 0, clampH > 0 else { return nil }
        let s = image.scale
        guard let cgCropped = image.cgImage?.cropping(to: CGRect(x: clampX * s, y: clampY * s, width: clampW * s, height: clampH * s)) else { return nil }
        let outW: CGFloat = 1200
        let outH = outW * (cropSize.height / cropSize.width)
        let fmt = UIGraphicsImageRendererFormat.default(); fmt.scale = 1
        return UIGraphicsImageRenderer(size: CGSize(width: outW, height: outH), format: fmt).image { _ in
            UIImage(cgImage: cgCropped, scale: 1, orientation: .up)
                .draw(in: CGRect(origin: .zero, size: CGSize(width: outW, height: outH)))
        }.jpegData(compressionQuality: 0.78)
    }

    private func downsampledImage(_ image: UIImage, maxDimension: CGFloat) -> UIImage {
        let size = image.size
        guard size.width > maxDimension || size.height > maxDimension else { return image }
        let ratio = min(maxDimension / size.width, maxDimension / size.height)
        let newSize = CGSize(width: size.width * ratio, height: size.height * ratio)
        let fmt = UIGraphicsImageRendererFormat.default(); fmt.scale = 1
        return UIGraphicsImageRenderer(size: newSize, format: fmt).image { _ in
            image.draw(in: CGRect(origin: .zero, size: newSize))
        }
    }

    private func rotatedImage(_ image: UIImage, turns: Int) -> UIImage {
        let t = ((turns % 4) + 4) % 4
        guard t > 0 else { return normalizedImage(image) }
        let src = normalizedImage(image)
        let origSize = src.size
        let newSize = t % 2 == 1 ? CGSize(width: origSize.height, height: origSize.width) : origSize
        let fmt = UIGraphicsImageRendererFormat.default(); fmt.scale = 1
        return UIGraphicsImageRenderer(size: newSize, format: fmt).image { ctx in
            let c = ctx.cgContext
            c.translateBy(x: newSize.width / 2, y: newSize.height / 2)
            c.rotate(by: CGFloat(t) * .pi / 2)
            src.draw(in: CGRect(x: -origSize.width / 2, y: -origSize.height / 2,
                                width: origSize.width, height: origSize.height))
        }
    }

    private func normalizedImage(_ image: UIImage) -> UIImage {
        guard image.imageOrientation != .up else { return image }
        let fmt = UIGraphicsImageRendererFormat.default(); fmt.scale = image.scale
        return UIGraphicsImageRenderer(size: image.size, format: fmt).image { _ in
            image.draw(in: CGRect(origin: .zero, size: image.size))
        }
    }
}

// MARK: - CropImageCanvas (isolated view — only this re-renders during pan/zoom)

private struct CropImageCanvas: View {
    let image: UIImage
    let containerSize: CGSize
    let cropSize: CGSize
    @Bindable var gestureState: CropGestureState
    @Binding var isDraggingCorner: Bool

    private var fillSize: CGSize {
        let imgW = image.size.width
        let imgH = image.size.height
        guard imgW > 0, imgH > 0 else { return containerSize }
        let targetW = cropSize.width > 0 ? cropSize.width : containerSize.width
        let targetH = cropSize.height > 0 ? cropSize.height : containerSize.height
        let baseScale = max(targetW / imgW, targetH / imgH)
        return CGSize(width: imgW * baseScale, height: imgH * baseScale)
    }

    var body: some View {
        Image(uiImage: image)
            .resizable()
            .scaledToFill()
            .frame(width: fillSize.width, height: fillSize.height)
            .scaleEffect(gestureState.scale)
            .offset(gestureState.offset)
            .frame(width: containerSize.width, height: containerSize.height)
            .contentShape(Rectangle())
            .gesture(panZoomGesture)
    }

    private var panZoomGesture: some Gesture {
        SimultaneousGesture(
            MagnificationGesture()
                .onChanged { v in
                    gestureState.showGrid = true
                    let s = min(max(gestureState.lastScale * v, 1.0), 5.0)
                    gestureState.scale = s
                    gestureState.offset = clampedOffset(gestureState.lastOffset, scale: s)
                }
                .onEnded { _ in
                    gestureState.lastScale = gestureState.scale
                    gestureState.lastOffset = gestureState.offset
                    scheduleGridHide()
                },
            DragGesture()
                .onChanged { v in
                    gestureState.showGrid = true
                    let proposed = CGSize(
                        width: gestureState.lastOffset.width + v.translation.width,
                        height: gestureState.lastOffset.height + v.translation.height
                    )
                    gestureState.offset = clampedOffset(proposed, scale: gestureState.scale)
                }
                .onEnded { _ in
                    gestureState.lastOffset = gestureState.offset
                    scheduleGridHide()
                }
        )
    }

    private func clampedOffset(_ proposed: CGSize, scale: CGFloat) -> CGSize {
        let fill = fillSize
        let maxX = max(0, (fill.width * scale - cropSize.width) / 2)
        let maxY = max(0, (fill.height * scale - cropSize.height) / 2)
        return CGSize(
            width: min(max(proposed.width, -maxX), maxX),
            height: min(max(proposed.height, -maxY), maxY)
        )
    }

    private func scheduleGridHide() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            if !isDraggingCorner { gestureState.showGrid = false }
        }
    }
}

// MARK: - CropOverlayView (only re-renders when cropSize or showGrid changes)

private struct CropOverlayView: View {
    let cropSize: CGSize
    let showGrid: Bool

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 2, style: .continuous)
                .stroke(Color.white.opacity(0.85), lineWidth: 1.2)

            Canvas { ctx, size in
                for i in 1...2 {
                    let x = size.width * CGFloat(i) / 3
                    var v = Path()
                    v.move(to: .init(x: x, y: 0))
                    v.addLine(to: .init(x: x, y: size.height))
                    ctx.stroke(v, with: .color(.white.opacity(0.25)), lineWidth: 0.5)

                    let y = size.height * CGFloat(i) / 3
                    var h = Path()
                    h.move(to: .init(x: 0, y: y))
                    h.addLine(to: .init(x: size.width, y: y))
                    ctx.stroke(h, with: .color(.white.opacity(0.25)), lineWidth: 0.5)
                }
            }
            .opacity(showGrid ? 1 : 0)
            .animation(.easeInOut(duration: 0.15), value: showGrid)

            ForEach(CropCorner.allCases, id: \.self) { c in
                CornerBracketShape(corner: c, armLength: 22)
                    .stroke(Color.white, style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))
            }
        }
        .frame(width: cropSize.width, height: cropSize.height)
    }
}

// MARK: - Supporting Types

private enum CropCorner: CaseIterable {
    case topLeft, topRight, bottomLeft, bottomRight
    var xSign: CGFloat { self == .topLeft || self == .bottomLeft ? -1 : 1 }
    var ySign: CGFloat { self == .topLeft || self == .topRight ? -1 : 1 }
}

private struct CropDimmingShape: Shape {
    let cropSize: CGSize
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.addRect(rect)
        p.addRoundedRect(
            in: CGRect(
                x: (rect.width - cropSize.width) / 2,
                y: (rect.height - cropSize.height) / 2,
                width: cropSize.width,
                height: cropSize.height
            ),
            cornerSize: CGSize(width: 2, height: 2)
        )
        return p
    }
}

private struct CornerBracketShape: Shape {
    let corner: CropCorner
    var armLength: CGFloat = 20

    func path(in rect: CGRect) -> Path {
        var p = Path()
        let x: CGFloat = corner == .topLeft || corner == .bottomLeft ? rect.minX : rect.maxX
        let y: CGFloat = corner == .topLeft || corner == .topRight ? rect.minY : rect.maxY
        let dx: CGFloat = corner == .topLeft || corner == .bottomLeft ? armLength : -armLength
        let dy: CGFloat = corner == .topLeft || corner == .topRight ? armLength : -armLength
        p.move(to: CGPoint(x: x + dx, y: y))
        p.addLine(to: CGPoint(x: x, y: y))
        p.addLine(to: CGPoint(x: x, y: y + dy))
        return p
    }
}
