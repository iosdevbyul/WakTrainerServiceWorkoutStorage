import Foundation
import SwiftData

@Model
final class WorkoutSessionEntity {
    @Attribute(.unique)
    var sessionID: UUID

    var workoutID: String
    var workoutName: String
    var startedAt: Date
    var endedAt: Date?
    var persistenceStateRawValue: String
    var syncStateRawValue: String
    var updatedAt: Date
    var payload: Data

    init(
        sessionID: UUID,
        workoutID: String,
        workoutName: String,
        startedAt: Date,
        endedAt: Date?,
        persistenceStateRawValue: String,
        syncStateRawValue: String,
        updatedAt: Date,
        payload: Data
    ) {
        self.sessionID = sessionID
        self.workoutID = workoutID
        self.workoutName = workoutName
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.persistenceStateRawValue = persistenceStateRawValue
        self.syncStateRawValue = syncStateRawValue
        self.updatedAt = updatedAt
        self.payload = payload
    }
}
