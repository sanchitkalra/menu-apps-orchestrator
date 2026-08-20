import Foundation

public actor Scheduler {
    private var timers: [String: Task<Void, Never>] = [:]
    private var onTick: ((String) async -> Void)?

    public init(onTick: ((String) async -> Void)? = nil) { self.onTick = onTick }

    public func register(appId: String, schedule: ScheduleConfig?) {
        cancel(appId: appId)
        guard let schedule else { return }
        if let interval = schedule.interval, let seconds = Self.parseInterval(interval) {
            let task = Task { [weak self] in
                while !Task.isCancelled {
                    try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
                    await self?.onTick?(appId)
                }
            }
            timers[appId] = task
        } else if let cron = schedule.cron {
            let task = Task { [weak self] in
                while !Task.isCancelled {
                    if let next = Self.nextCronDate(cron: cron) {
                        let delay = next.timeIntervalSinceNow
                        if delay > 0 {
                            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                        }
                    } else {
                        try? await Task.sleep(nanoseconds: 300 * 1_000_000_000)
                    }
                    if Task.isCancelled { break }
                    await self?.onTick?(appId)
                }
            }
            timers[appId] = task
        }
    }

    public func cancel(appId: String) {
        timers[appId]?.cancel()
        timers.removeValue(forKey: appId)
    }

    public func cancelAll() {
        for t in timers.values { t.cancel() }
        timers.removeAll()
    }

    static func parseInterval(_ s: String) -> Double? {
        if s.hasSuffix("ms"), let v = Double(s.dropLast(2)) { return v/1000 }
        if s.hasSuffix("s"), let v = Double(s.dropLast(1)) { return v }
        if s.hasSuffix("m"), let v = Double(s.dropLast(1)) { return v*60 }
        if s.hasSuffix("h"), let v = Double(s.dropLast(1)) { return v*3600 }
        return Double(s)
    }

    // Minimal cron: 5 fields minute hour day month weekday, supports * , */N , single int
    static func nextCronDate(cron: String) -> Date? {
        let parts = cron.split(separator: " ").map(String.init)
        guard parts.count == 5 else { return nil }
        let cal = Calendar.current
        var d = Date().addingTimeInterval(60) // next minute
        d = cal.date(bySetting: .second, value: 0, of: d) ?? d
        for _ in 0..<525600 { // 1 year of minutes
            let comps = cal.dateComponents([.minute, .hour, .day, .month, .weekday], from: d)
            if matchesCron(parts: parts, comps: comps) { return d }
            guard let nd = cal.date(byAdding: .minute, value: 1, to: d) else { return nil }
            d = nd
        }
        return nil
    }

    static func matchesCron(parts: [String], comps: DateComponents) -> Bool {
        // minute hour day month weekday (weekday 0-7, Sunday 0 or 7)
        let vals = [comps.minute ?? -1, comps.hour ?? -1, comps.day ?? -1, comps.month ?? -1, (comps.weekday ?? 1) - 1]
        for i in 0..<5 {
            let p = parts[i]
            let v = vals[i]
            if p == "*" { continue }
            if p.hasPrefix("*/"), let n = Int(p.dropFirst(2)), n > 0 {
                if v % n != 0 { return false }
                continue
            }
            if let n = Int(p), n == v { continue }
            // support comma list like 1,2,3
            if p.contains(",") {
                let opts = p.split(separator: ",").compactMap { Int($0) }
                if opts.contains(v) { continue }
                return false
            }
            return false
        }
        return true
    }
}
