import SwiftUI

/// Draws the enlarged-preview stage. It is purely visual: the panel ignores the mouse so hover and
/// clicks keep reaching the Peek cards, and VoiceOver keeps using the cards, which carry the labels.
struct WindowPeekStageView: View {
    let stage: WindowPeekStage
    var reduceTransparencyOverride: Bool? = nil
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        ZStack(alignment: .topLeading) {
            WindowPeekStageDim(cutout: stage.cutout)
                .fill(.black.opacity(0.24), style: FillStyle(eoFill: true))
                .opacity(stage.dimmed ? 1 : 0)
            ForEach(stage.exhibits) { exhibit in
                WindowPeekExhibitView(exhibit: exhibit, opaque: reduceTransparencyOverride ?? reduceTransparency)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// The whole stage minus a rounded hole over the Peek panel, filled with the even-odd rule.
/// The radius is the card's 16 plus the panel's 6-point padding, so the hole stays concentric.
private struct WindowPeekStageDim: Shape {
    let cutout: CGRect

    func path(in rect: CGRect) -> Path {
        var path = Path(rect)
        if !cutout.isEmpty { path.addRoundedRect(in: cutout, cornerSize: CGSize(width: 22, height: 22)) }
        return path
    }
}

/// One exhibit: the image laid out at its hero frame with a title placard beneath it.
private struct WindowPeekExhibitView: View {
    let exhibit: WindowPeekExhibit
    let opaque: Bool

    var body: some View {
        let pose = exhibit.pose
        ZStack(alignment: .topLeading) {
            artwork(pose: pose)
            WindowPeekPlacard(title: exhibit.title, opaque: opaque)
                .frame(width: exhibit.hero.width)
                .offset(y: exhibit.hero.height + 14)
                .opacity(exhibit.lifted && !exhibit.leaving && exhibit.landing == nil ? 1 : 0)
        }
        .offset(x: exhibit.hero.minX, y: exhibit.hero.minY)
        .onAppear {
            // The first frame renders at the card; animating afterwards is what makes it fly.
            withAnimation(exhibit.liftAnimation) { exhibit.lifted = true }
        }
    }

    private func artwork(pose: WindowPeekExhibitPose) -> some View {
        ZStack {
            image(exhibit.preview)
            if let detail = exhibit.detail {
                image(detail).transition(.opacity)
            }
        }
        .animation(.easeOut(duration: 0.22), value: exhibit.detail != nil)
        .frame(width: exhibit.hero.width, height: exhibit.hero.height)
        .clipShape(.rect(cornerRadius: pose.cornerRadius))
        .shadow(color: .black.opacity(0.35 * pose.opacity), radius: 28, y: 12)
        .scaleEffect(x: pose.scale.width, y: pose.scale.height, anchor: .topLeading)
        .offset(pose.offset)
        .opacity(pose.opacity)
    }

    private func image(_ image: CGImage) -> some View {
        Image(decorative: image, scale: 1)
            .resizable()
            .interpolation(.high)
            .aspectRatio(contentMode: .fill)
            .frame(width: exhibit.hero.width, height: exhibit.hero.height)
            .clipped()
    }
}

/// The window's title under the exhibit, like a museum label.
private struct WindowPeekPlacard: View {
    let title: String
    let opaque: Bool

    var body: some View {
        Text(verbatim: title)
            .font(.callout.weight(.medium))
            .lineLimit(1)
            .truncationMode(.middle)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background {
                ZStack {
                    Capsule().fill(opaque ? AnyShapeStyle(Color(nsColor: .windowBackgroundColor))
                                          : AnyShapeStyle(.regularMaterial))
                    StudioMarkUnderlay()
                }
                .clipShape(Capsule())
            }
            .frame(maxWidth: .infinity)
    }
}

#if DEBUG
/// Synthetic window artwork. Previews never capture the user's windows.
private func windowPeekStagePreviewImage(width: Int, height: Int) -> CGImage? {
    guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { return nil }
    let w = CGFloat(width), h = CGFloat(height)
    context.setFillColor(CGColor(gray: 0.97, alpha: 1))
    context.fill(CGRect(x: 0, y: 0, width: w, height: h))
    context.setFillColor(CGColor(red: 0.2, green: 0.4, blue: 0.7, alpha: 1))
    context.fill(CGRect(x: 0, y: h * 0.9, width: w, height: h * 0.1))
    context.setFillColor(CGColor(gray: 0.7, alpha: 1))
    for row in 0..<8 {
        context.fill(CGRect(x: w * 0.06, y: h * (0.78 - CGFloat(row) * 0.09), width: w * (0.7 - CGFloat(row) * 0.05),
                            height: h * 0.025))
    }
    return context.makeImage()
}

@MainActor private func windowPeekPreviewStage(lifted: Bool, reduceMotion: Bool = false,
                                               title: String = "Quarterly Report.pages") -> WindowPeekStage {
    let stage = WindowPeekStage()
    stage.cutout = CGRect(x: 250, y: 520, width: 520, height: 180)
    stage.dimmed = true
    if let preview = windowPeekStagePreviewImage(width: 480, height: 300) {
        let exhibit = WindowPeekExhibit(token: ApplicationWindowToken(sessionID: UUID(), id: UUID()), title: title,
                                        preview: preview, detail: windowPeekStagePreviewImage(width: 1280, height: 800),
                                        source: CGRect(x: 270, y: 540, width: 240, height: 150),
                                        hero: CGRect(x: 190, y: 60, width: 640, height: 400), reduceMotion: reduceMotion)
        exhibit.lifted = lifted
        stage.exhibits = [exhibit]
    }
    return stage
}

#Preview("Staged exhibit") {
    WindowPeekStageView(stage: windowPeekPreviewStage(lifted: true))
        .frame(width: 1020, height: 720)
        .background(.teal.gradient)
}
#Preview("Flight from card (plays on appear)") {
    WindowPeekStageView(stage: windowPeekPreviewStage(lifted: false))
        .frame(width: 1020, height: 720)
        .background(.indigo.gradient)
}
#Preview("Reduce Motion fade, German, opaque placard") {
    WindowPeekStageView(stage: windowPeekPreviewStage(lifted: false, reduceMotion: true,
                                                     title: "Ein Dokument mit einem absichtlich sehr langen Fenstertitel"),
                        reduceTransparencyOverride: true)
        .environment(\.locale, Locale(identifier: "de"))
        .preferredColorScheme(.dark)
        .frame(width: 1020, height: 720)
        .background(.orange.gradient)
}
#endif
