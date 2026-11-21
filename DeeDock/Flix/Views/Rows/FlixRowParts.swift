import SwiftUI

/// A row's second line: what the window asks for (Fits), a ✦ caption, or the coloured event with
/// its folder, then up to two fact chips. One line; text gives way before chips do.
struct FlixRowSubtitle: View {
    let item: FlixItem
    let context: FlixRowContext
    let annotation: FlixItemAnnotation?
    let selected: Bool

    var body: some View {
        HStack(spacing: 5) {
            if context.match == .meaning { FlixMeaningChip(selected: selected) }
            if let phrase = context.fitPhrase {
                FlixSparkle(size: 10, selected: selected)
                Text(.flixFitAsksFor(phrase))
                if let memory = context.memory {
                    Label { Text(verbatim: memory.text) } icon: {
                        Image(systemName: "arrow.counterclockwise").font(.system(size: 8.5, weight: .bold))
                    }
                    .labelStyle(FlixCompactLabelStyle())
                    .opacity(0.8)
                }
                if let conversion = context.conversion {
                    FlixConversionChip(text: conversion, selected: selected)
                        .transition(.opacity)
                }
            } else if let caption = annotation?.caption {
                FlixSparkle(size: 10, selected: selected)
                Text(verbatim: caption).layoutPriority(1)
                if annotation?.isSensitive == true { Text(verbatim: "· " + String(localized: .flixPreviewHidden)) }
                Text(verbatim: "·")
                FlixEventLabel(item: item, selected: selected, short: true, plain: true)
            } else {
                FlixEventLabel(item: item, selected: selected).layoutPriority(1)
                if let folder = item.folderName { Text(verbatim: "· " + folder) }
                if let relation = context.relation { Text(verbatim: "· " + relation) }
            }
            ForEach(Array((annotation?.facts ?? []).prefix(2).enumerated()), id: \.offset) { _, fact in
                FlixFactChip(fact: fact, selected: selected)
                    .transition(.opacity)
            }
        }
        .font(.system(size: 11))
        .lineLimit(1)
        .truncationMode(.tail)
        .foregroundStyle(selected ? Color.white.opacity(0.82) : Color.secondary)
    }
}

/// A ✦ suggestion on a row: "✦ Move to Finance", "✦ Rename".
struct FlixActionPill: View {
    let title: String
    let selected: Bool
    let action: () -> Void
    @State private var hovered = false

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: FlixStyle.controlRadius, style: .continuous)
        Button(action: action) {
            Text(verbatim: "✦ " + title)
                .lineLimit(1)
                .truncationMode(.middle)
                .font(.system(size: 11, weight: .semibold))
            .padding(.horizontal, 8)
            .frame(height: 22)
            .foregroundStyle(selected ? Color.white : FlixStyle.aiViolet)
            .background(selected ? Color.white.opacity(hovered ? 0.3 : 0.22) : FlixStyle.aiSoft, in: shape)
            .overlay {
                if !selected { shape.strokeBorder(FlixStyle.aiStroke, lineWidth: 0.5) }
            }
            .brightness(hovered && !selected ? 0.08 : 0)
            .contentShape(.rect)
            .contentShape(.focusEffect, shape)
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
        .animation(FlixMotion.hover, value: hovered)
        .accessibilityLabel(Text(verbatim: title))
    }
}

/// "3 versions ⌄": shows or hides the older versions under a row. The chevron turns over.
struct FlixVersionsPill: View {
    let count: Int
    let expanded: Bool
    let selected: Bool
    var reduceMotion = false
    let action: () -> Void
    @State private var hovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 3) {
                Text(.flixVersionsCount(count))
                Image(systemName: "chevron.down")
                    .font(.system(size: 7, weight: .bold))
                    .rotationEffect(.degrees(expanded ? 180 : 0))
                    .animation(FlixMotion.resolved(FlixMotion.pill, reduceMotion: reduceMotion), value: expanded)
            }
            .font(.system(size: 10.5, weight: .semibold))
            .padding(.horizontal, 6)
            .frame(height: 18)
            .foregroundStyle(selected ? Color.white : hovered ? Color.primary : Color.secondary)
            .background(selected ? Color.white.opacity(0.22) : FlixStyle.chipHover,
                        in: RoundedRectangle(cornerRadius: 6, style: .continuous))
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .fixedSize()
        .onHover { hovered = $0 }
        .accessibilityAddTraits(expanded ? .isSelected : [])
    }
}

/// The elbow joining an older version to its newest one.
struct FlixVersionConnector: View {
    var body: some View {
        Path { path in
            path.move(to: CGPoint(x: 10, y: -6))
            path.addLine(to: CGPoint(x: 10, y: 16))
            path.addQuadCurve(to: CGPoint(x: 16, y: 22), control: CGPoint(x: 10, y: 22))
            path.addLine(to: CGPoint(x: 18, y: 22))
        }
        .stroke(FlixStyle.outline, style: StrokeStyle(lineWidth: 1.5, lineCap: .round))
        .frame(width: 22, height: 22)
        .accessibilityHidden(true)
    }
}
