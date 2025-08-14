import Foundation

public final class SpeedMeter {
    private var lastTimestamp: TimeInterval?
    private var lastBytes: Int64 = 0
    private var lastSpeed: Double = 0
    private var lastProgressTime: TimeInterval?

    public init() {}

    private func monotonicNow() -> TimeInterval {
        // Monotonic clock avoids wall-clock jumps affecting speed calculation
        ProcessInfo.processInfo.systemUptime
    }

    public func update(totalBytes: Int64) -> Double {
        let now = monotonicNow()
        guard let lastTimestamp else {
            self.lastTimestamp = now
            self.lastBytes = totalBytes
            return 0
        }
        let deltaTime = now - lastTimestamp

        // Minimum interval to avoid noisy updates
        let minimumInterval: Double = 0.25
        if deltaTime < minimumInterval {
            return lastSpeed
        }

        let bytesDelta = totalBytes - lastBytes
        if bytesDelta <= 0 {
            // If no progress, keep showing last known speed for a grace window
            let staleAfter: Double = 1.5
            if let lastProgressTime, now - lastProgressTime > staleAfter {
                lastSpeed = 0
            }
            // Advance timestamp so future deltas reflect recent interval
            self.lastTimestamp = now
            return lastSpeed
        }

        // Instantaneous speed
        let instant = Double(bytesDelta) / deltaTime
        // Exponential smoothing to reduce flicker
        let alpha = 0.3
        lastSpeed = lastSpeed > 0 ? (alpha * instant + (1 - alpha) * lastSpeed) : instant
        lastProgressTime = now
        self.lastTimestamp = now
        self.lastBytes = totalBytes
        return max(0, lastSpeed)
    }
}


