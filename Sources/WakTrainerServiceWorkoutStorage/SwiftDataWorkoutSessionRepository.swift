import Foundation
import SwiftData
import WakTrainerCoreModels
import WakTrainerDomainWorkout

@MainActor
public final class SwiftDataWorkoutSessionRepository: WorkoutSessionRepository, WorkoutPauseRestoreStorage {
    private let modelContainer: ModelContainer
    private let modelContext: ModelContext
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder
    private let ownerUserID: UUID?

    public init(
        inMemory: Bool = false,
        ownerUserID: UUID? = nil
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

        self.ownerUserID = ownerUserID
        self.encoder = JSONEncoder()
        self.decoder = JSONDecoder()
    }

    public func fetchCompletedSession(id: UUID) async throws -> WorkoutSession? {
        guard let stored = try await fetchSession(id: id),
              stored.persistenceState == .completed else {
            return nil
        }
        return stored.session
    }

    /// Compare and replace within one SwiftData ModelContext transaction.
    /// All writes to this repository must use the same context to preserve
    /// serialization; SwiftData does not expose a cross-process SQL CAS here.
    public func compareAndReplaceCompleted(
        expected: WorkoutSession,
        replacement: WorkoutSession
    ) async throws -> Bool {
        guard expected.id == replacement.id,
              replacement.timing.endDate != nil else {
            return false
        }
        let sessionID = expected.id
        let owner = ownerUserID
        let completed = WorkoutSessionPersistenceState.completed.rawValue
        let replacementPayload = try encoder.encode(replacement)

        return try modelContext.transaction {
            let descriptor = FetchDescriptor<WorkoutSessionEntity>(
                predicate: #Predicate {
                    $0.sessionID == sessionID && $0.ownerUserID == owner
                }
            )
            guard let entity = try modelContext.fetch(descriptor).first,
                  entity.persistenceStateRawValue == completed,
                  try decoder.decode(WorkoutSession.self, from: entity.payload) == expected else {
                return false
            }

            entity.payload = replacementPayload
            entity.workoutID = replacement.workout.workoutID
            entity.workoutName = replacement.workout.name
            entity.startedAt = replacement.timing.startDate
            entity.endedAt = replacement.timing.endDate
            entity.syncStateRawValue = WorkoutSessionSyncState.pending.rawValue
            entity.updatedAt = Date()
            try modelContext.save()
            return true
        }
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
        let ownerUserID = self.ownerUserID
        let descriptor = FetchDescriptor<WorkoutSessionEntity>(
            predicate: #Predicate {
                $0.sessionID == id && $0.ownerUserID == ownerUserID
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
        let ownerUserID = self.ownerUserID
        var descriptor = FetchDescriptor<WorkoutSessionEntity>(
            predicate: #Predicate { $0.ownerUserID == ownerUserID }
        )
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
        let ownerUserID = self.ownerUserID
        let inProgressRawValue =
            WorkoutSessionPersistenceState.inProgress.rawValue

        var descriptor = FetchDescriptor<WorkoutSessionEntity>(
            predicate: #Predicate {
                $0.persistenceStateRawValue == inProgressRawValue &&
                $0.ownerUserID == ownerUserID
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
        let ownerUserID = self.ownerUserID
        guard startDate < endDate else {
            return []
        }

        let completedRawValue =
            WorkoutSessionPersistenceState.completed.rawValue

        var descriptor = FetchDescriptor<WorkoutSessionEntity>(
            predicate: #Predicate {
                $0.persistenceStateRawValue == completedRawValue &&
                $0.ownerUserID == ownerUserID &&
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

    /// Only explicitly owned records can ever be uploaded.
    /// Legacy records with no owner are excluded.
    public func fetchPendingUploads() async throws -> [StoredWorkoutSession] {
        guard let ownerUserID else { return [] }
        let completed = WorkoutSessionPersistenceState.completed.rawValue
        let synced = WorkoutSessionSyncState.synced.rawValue
        var descriptor = FetchDescriptor<WorkoutSessionEntity>(
            predicate: #Predicate {
                $0.ownerUserID == ownerUserID &&
                $0.persistenceStateRawValue == completed &&
                $0.syncStateRawValue != synced
            }
        )
        descriptor.sortBy = [SortDescriptor(\.startedAt, order: .forward)]
        return try modelContext.fetch(descriptor).map(makeStoredSession)
    }

    public func updateSyncState(
        for sessionID: UUID,
        to state: WorkoutSessionSyncState
    ) async throws {
        guard let ownerUserID else {
            throw WorkoutStorageError.accountRequired
        }
        let descriptor = FetchDescriptor<WorkoutSessionEntity>(
            predicate: #Predicate {
                $0.sessionID == sessionID && $0.ownerUserID == ownerUserID
            }
        )
        guard let entity = try modelContext.fetch(descriptor).first else {
            throw WorkoutStorageError.sessionNotFound
        }
        guard entity.persistenceStateRawValue ==
                WorkoutSessionPersistenceState.completed.rawValue else {
            throw WorkoutStorageError.sessionNotCompleted
        }
        entity.syncStateRawValue = state.rawValue
        entity.updatedAt = Date()
        try modelContext.save()
    }

    public func deleteSession(
        id: UUID
    ) async throws {
        let ownerUserID = self.ownerUserID
        let descriptor = FetchDescriptor<WorkoutSessionEntity>(
            predicate: #Predicate {
                $0.sessionID == id && $0.ownerUserID == ownerUserID
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
        let ownerUserID = self.ownerUserID
        let descriptor = FetchDescriptor<WorkoutSessionEntity>(
            predicate: #Predicate { $0.ownerUserID == ownerUserID }
        )
        for entity in try modelContext.fetch(descriptor) {
            modelContext.delete(entity)
        }
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
            guard entity.ownerUserID == ownerUserID else {
                throw WorkoutStorageError.ownerMismatch
            }
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
                    ownerUserID: ownerUserID,
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
    case sessionNotFound
    case sessionNotCompleted
    case accountRequired
    case ownerMismatch
}
