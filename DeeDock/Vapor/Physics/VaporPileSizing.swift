import CoreGraphics

/// Sizes for the folder icons inside the orb: bigger folders get bigger icons on a log scale,
/// and every icon shrinks together when the pile would overflow the sphere.
///
/// The physics treats each icon as a circle of ``radius(bytes:)``; the drawn folder is
/// ``iconWidth(radius:)`` wide, a little wider than that circle, so neighbours overlap slightly
/// the way stacked folders do.
nonisolated enum VaporPileSizing {
    /// The radius used while a folder is still being measured.
    static let pendingRadius: Double = 9

    /// A body's collision radius, 7.5…15.5 pt, from the folder's allocated size.
    static func radius(bytes: Int64) -> Double {
        guard bytes > 0 else { return pendingRadius }
        let megabytes = Double(bytes) / 1_000_000
        return min(max(7 + 2.1 * log10(megabytes + 1), 7.5), 15.5)
    }

    /// The radius for a folder's current measurement.
    static func radius(for measurement: VaporMeasurement) -> Double {
        measurement.isPending ? pendingRadius : radius(bytes: measurement.bytes)
    }

    /// The factor that makes all bodies fit in about half the sphere's area: 1 when they
    /// already fit, smaller when the pile would overflow.
    static func fitScale(radii: [Double], innerRadius: Double) -> Double {
        let area = radii.reduce(0) { $0 + $1 * $1 }
        guard area > 0 else { return 1 }
        return min(1, (0.52 * innerRadius * innerRadius / area).squareRoot())
    }

    /// The width of the folder drawn for a body: 2.3 radii, as in the mockup.
    static func iconWidth(radius: Double) -> Double { radius * 2.3 }
}
