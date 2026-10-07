import Foundation
import SwiftData
import WakTrainerCoreModels
import WakTrainerDomainWorkout

@MainActor
public final class SwiftDataWorkoutSessionRepository: WorkoutSessionRepository {
    private let modelContainer: ModelContainer
    private let modelContext: ModelContext
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    public init(
        inMemory: Bool = false
    ) throws {
        let configuration = ModelConfiguration(
            isStoredInMemoryOnly: inMemory
        )

        self.modelContainer = try ModelContainer(
            for: WorkoutSessionEntity.self,
            configurations: configuration
        )

        self.modelContext = ModelContext(
            modelContainer
        )

        self.encoder = JSONEncoder()
        self.decoder = JSONDecoder()
    }

    public func saveCheckpoint(
        _ session: WorkoutSession
    ) async throws {
        try upsert(
            session,
            persistenceState: .inProgress,
            syncState: .pending
        )
    }

    public func saveCompleted(
        _ session: WorkoutSession
    ) async throws {
        try upsert(
            session,
            persistenceState: .completed,
            syncState: .pending
        )
    }

    public func fetchSession(
        id: UUID
    ) async throws -> StoredWorkoutSession? {
        let descriptor = FetchDescriptor<WorkoutSessionEntity>(
            predicate: #Predicate {
                $0.sessionID == id
            }
        )

        guard let entity = try modelContext.fetch(
            descriptor
        ).first else {
            return nil
        }

        return try makeStoredSession(
            from: entity
        )
    }

    public func fetchSessions() async throws -> [StoredWorkoutSession] {
        var descriptor = FetchDescriptor<WorkoutSessionEntity>()
        descriptor.sortBy = [
            SortDescriptor(
                \.startedAt,
                order: .reverse
            )
        ]

        return try modelContext.fetch(
            descriptor
        )
        .map(makeStoredSession)
    }

    public func fetchIncompleteSessions() async throws -> [StoredWorkoutSession] {
        let inProgressRawValue =
            WorkoutSessionPersistenceState.inProgress.rawValue

        var descriptor = FetchDescriptor<WorkoutSessionEntity>(
            predicate: #Predicate {
                $0.persistenceStateRawValue == inProgressRawValue
            }
        )

        descriptor.sortBy = [
            SortDescriptor(
                \.updatedAt,
                order: .reverse
            )
        ]

        return try modelContext.fetch(
            descriptor
        )
        .map(makeStoredSession)
    }

    public func fetchCompletedSessions(
        from startDate: Date,
        to endDate: Date
    ) async throws -> [StoredWorkoutSession] {
        guard startDate < endDate else {
            return []
        }

        let completedRawValue =
            WorkoutSessionPersistenceState.completed.rawValue

        var descriptor = FetchDescriptor<WorkoutSessionEntity>(
            predicate: #Predicate {
                $0.persistenceStateRawValue == completedRawValue &&
                $0.startedAt >= startDate &&
                $0.startedAt < endDate
            }
        )

        descriptor.sortBy = [
            SortDescriptor(
                \.startedAt,
                order: .forward
            )
        ]

        return try modelContext.fetch(
            descriptor
        )
        .map(makeStoredSession)
    }

    public func deleteSession(
        id: UUID
    ) async throws {
        let descriptor = FetchDescriptor<WorkoutSessionEntity>(
            predicate: #Predicate {
                $0.sessionID == id
            }
        )

        for entity in try modelContext.fetch(
            descriptor
        ) {
            modelContext.delete(entity)
        }

        try modelContext.save()
    }

    public func deleteAllSessions() async throws {
        try modelContext.delete(
            model: WorkoutSessionEntity.self
        )
        try modelContext.save()
    }
}

private extension SwiftDataWorkoutSessionRepository {
    func upsert(
        _ session: WorkoutSession,
        persistenceState: WorkoutSessionPersistenceState,
        syncState: WorkoutSessionSyncState
    ) throws {
        let sessionID = session.id
        let payload = try encoder.encode(
            session
        )
        let now = Date()

        let descriptor = FetchDescriptor<WorkoutSessionEntity>(
            predicate: #Predicate {
                $0.sessionID == sessionID
            }
        )

        if let entity = try modelContext.fetch(
            descriptor
        ).first {
            entity.workoutID = session.workout.workoutID
            entity.workoutName = session.workout.name
            entity.startedAt = session.timing.startDate
            entity.endedAt = session.timing.endDate
            entity.persistenceStateRawValue = persistenceState.rawValue
            entity.syncStateRawValue = syncState.rawValue
            entity.updatedAt = now
            entity.payload = payload
        } else {
            modelContext.insert(
                WorkoutSessionEntity(
                    sessionID: session.id,
                    workoutID: session.workout.workoutID,
                    workoutName: session.workout.name,
                    startedAt: session.timing.startDate,
                    endedAt: session.timing.endDate,
                    persistenceStateRawValue: persistenceState.rawValue,
                    syncStateRawValue: syncState.rawValue,
                    updatedAt: now,
                    payload: payload
                )
            )
        }

        try modelContext.save()
    }

    func makeStoredSession(
        from entity: WorkoutSessionEntity
    ) throws -> StoredWorkoutSession {
        guard let persistenceState =
                WorkoutSessionPersistenceState(
                    rawValue: entity.persistenceStateRawValue
                ),
              let syncState =
                WorkoutSessionSyncState(
                    rawValue: entity.syncStateRawValue
                ) else {
            throw WorkoutStorageError.invalidStoredMetadata
        }

        let session = try decoder.decode(
            WorkoutSession.self,
            from: entity.payload
        )

        return StoredWorkoutSession(
            session: session,
            persistenceState: persistenceState,
            syncState: syncState,
            updatedAt: entity.updatedAt
        )
    }
}

public enum WorkoutStorageError: Error, Equatable {
    case invalidStoredMetadata
}
