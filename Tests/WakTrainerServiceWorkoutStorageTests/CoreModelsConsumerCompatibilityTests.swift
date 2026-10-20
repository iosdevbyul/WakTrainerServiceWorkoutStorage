import Foundation
import CoreLocation
import Testing
import WakTrainerCoreModels
import WakTrainerDomainWorkout

@Suite("CoreModels consumer compatibility")
struct CoreModelsConsumerCompatibilityTests {
    @Test("Persisted workout exercise equipment still supports existing CoreModels API")
    func strengthEquipmentRoundTrip() throws {
        let record = WorkoutExerciseRecord(
            name: "Bench Press",
            kind: .strength,
            strengthEquipment: .barbell,
            startDate: Date(timeIntervalSince1970: 1_800_000_000)
        )
        let encoded = try JSONEncoder().encode(record)
        let restored = try JSONDecoder().decode(WorkoutExerciseRecord.self, from: encoded)
        #expect(restored.strengthEquipment == .barbell)
    }

    @Test("Legacy route coordinates remain available for persisted workout sessions")
    func legacyRouteRoundTrip() throws {
        let session = WorkoutSessionData(
            startDate: Date(timeIntervalSince1970: 1_800_000_000),
            routeLocations: [
                CLLocationCoordinate2D(latitude: 37.5665, longitude: 126.9780)
            ]
        )
        let encoded = try JSONEncoder().encode(session)
        let restored = try JSONDecoder().decode(WorkoutSessionData.self, from: encoded)
        #expect(restored.routeLocations.count == 1)
        #expect(restored.routeLocations[0].latitude == 37.5665)
        #expect(restored.routeLocations[0].longitude == 126.9780)
    }
}
