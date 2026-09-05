import Foundation
import HealthKit

public final class StepCountReader: @unchecked Sendable {
    public static let shared = StepCountReader()

    private let healthStore: HKHealthStore?

    public init(healthStore: HKHealthStore? = HKHealthStore.isHealthDataAvailable() ? HKHealthStore() : nil) {
        self.healthStore = healthStore
    }

    /// Fetches the cumulative step count for the exact date interval [startDate, endDate].
    /// Returns the step count as an Int, or nil if unavailable, unauthorized, or unsupported.
    public func fetchStepCount(startDate: Date, endDate: Date) async -> Int? {
        guard startDate < endDate else { return nil }
        guard let healthStore = self.healthStore, HKHealthStore.isHealthDataAvailable() else { return nil }
        guard let stepType = HKQuantityType.quantityType(forIdentifier: .stepCount) else { return nil }

        do {
            let status = try await healthStore.statusForAuthorizationRequest(toShare: [], read: [stepType])
            if status == .shouldRequest {
                try await healthStore.requestAuthorization(toShare: [], read: [stepType])
            }

            let predicate = Self.makeSamplePredicate(startDate: startDate, endDate: endDate)
            let samplePredicate = HKSamplePredicate.quantitySample(type: stepType, predicate: predicate)
            let descriptor = HKStatisticsQueryDescriptor(predicate: samplePredicate, options: .cumulativeSum)
            let statistics = try await descriptor.result(for: healthStore)

            guard let sumQuantity = statistics?.sumQuantity() else {
                return nil
            }
            let steps = sumQuantity.doubleValue(for: .count())
            return Int(steps.rounded())
        } catch {
            return nil
        }
    }

    // MARK: - Predicate & Query Construction Helpers

    /// Builds a sample predicate covering [startDate, endDate] with options: [] to allow overlapping boundary samples.
    public static func makeSamplePredicate(startDate: Date, endDate: Date) -> NSPredicate {
        HKQuery.predicateForSamples(withStart: startDate, end: endDate, options: [])
    }

    // MARK: - Formatting Helpers

    public static func formatTimeInterval(
        start: Date,
        end: Date,
        locale: Locale = .current,
        timeZone: TimeZone = .current
    ) -> String {
        let formatter = DateIntervalFormatter()
        formatter.locale = locale
        formatter.timeZone = timeZone
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return formatter.string(from: start, to: end)
    }

    public static func formatDurationMinutes(_ duration: TimeInterval) -> String {
        let minutes = max(1, Int((duration / 60.0).rounded()))
        return "\(minutes) min"
    }

    public static func formatStepCount(_ count: Int?) -> String {
        guard let count = count else {
            return "Steps unavailable"
        }
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        let formattedNumber = formatter.string(from: NSNumber(value: count)) ?? "\(count)"
        return count == 1 ? "1 step" : "\(formattedNumber) steps"
    }
}
