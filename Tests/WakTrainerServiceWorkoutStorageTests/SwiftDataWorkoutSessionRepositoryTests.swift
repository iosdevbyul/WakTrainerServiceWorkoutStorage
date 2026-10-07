import Foundation
import Testing
import WakTrainerCoreModels
import WakTrainerDomainWorkout

@testable import WakTrainerServiceWorkoutStorage

@MainActor
@Suite("SwiftDataWorkoutSessionRepository")
struct SwiftDataWorkoutSessionRepositoryTests {

    @Test("checkpoint persists the complete WorkoutSession payload")
    func checkpointPersistsSession() async throws {
        let repository = try SwiftDataWorkoutSessionRepository(
            inMemory: true
        )
        let session = makeSession(
            completed: false
        )

        try await repository.saveCheckpoint(
            session
        )

        let stored = try #require(
            try await repository.fetchSession(
                id: session.id
            )
        )

        #expect(stored.session == session)
        #expect(stored.persistenceState == .inProgress)
        #expect(stored.syncState == .pending)
    }

    @Test("completed save replaces the checkpoint for the same session")
    func completedSaveUpsertsCheckpoint() async throws {
        let repository = try SwiftDataWorkoutSessionRepository(
            inMemory: true
        )
        var session = makeSession(
            completed: false
        )

        try await repository.saveCheckpoint(
            session
        )

        session.timing.endDate =
            session.timing.startDate
                .addingTimeInterval(1_800)
        session.timing.elapsedDuration = 1_800
        session.timing.activeDuration = 1_500
        session.timing.pausedDuration = 300

        try await repository.saveCompleted(
            session
        )

        let all = try await repository.fetchSessions()
        let stored = try #require(all.first)

        #expect(all.count == 1)
        #expect(stored.session == session)
        #expect(stored.persistenceState == .completed)
        #expect(stored.syncState == .pending)
        #expect(
            try await repository.fetchIncompleteSessions()
                .isEmpty
        )
    }

    @Test("incomplete sessions can be restored after a new repository instance")
    func fetchesIncompleteSessions() async throws {
        let repository = try SwiftDataWorkoutSessionRepository(
            inMemory: true
        )
        let first = makeSession(
            id: UUID(),
            startedAt: Date(
                timeIntervalSince1970: 1_800_000_000
            ),
            completed: false
        )
        let second = makeSession(
            id: UUID(),
            startedAt: Date(
                timeIntervalSince1970: 1_800_001_000
            ),
            completed: false
        )

        try await repository.saveCheckpoint(first)
        try await repository.saveCheckpoint(second)

        let incomplete = try await repository
            .fetchIncompleteSessions()

        #expect(incomplete.count == 2)
        #expect(
            Set(incomplete.map(\.session.id))
                == Set([first.id, second.id])
        )
    }


    @Test("completed sessions are filtered by start date range and ordered ascending")
    func fetchesCompletedSessionsInRange() async throws {
        let repository = try SwiftDataWorkoutSessionRepository(
            inMemory: true
        )

        let rangeStart = Date(
            timeIntervalSince1970: 1_800_000_000
        )
        let rangeEnd =
            rangeStart.addingTimeInterval(86_400)

        let before = makeSession(
            id: UUID(),
            startedAt:
                rangeStart.addingTimeInterval(-1),
            completed: true
        )
        let atStart = makeSession(
            id: UUID(),
            startedAt: rangeStart,
            completed: true
        )
        let later = makeSession(
            id: UUID(),
            startedAt:
                rangeStart.addingTimeInterval(3_600),
            completed: true
        )
        let atEnd = makeSession(
            id: UUID(),
            startedAt: rangeEnd,
            completed: true
        )
        let inProgress = makeSession(
            id: UUID(),
            startedAt:
                rangeStart.addingTimeInterval(1_800),
            completed: false
        )

        try await repository.saveCompleted(before)
        try await repository.saveCompleted(atStart)
        try await repository.saveCompleted(later)
        try await repository.saveCompleted(atEnd)
        try await repository.saveCheckpoint(inProgress)

        let sessions =
            try await repository.fetchCompletedSessions(
                from: rangeStart,
                to: rangeEnd
            )

        #expect(
            sessions.map(\.session.id)
                == [atStart.id, later.id]
        )
        #expect(
            sessions.allSatisfy {
                $0.persistenceState == .completed
            }
        )
    }

    @Test("invalid completed-session range returns empty results")
    func invalidCompletedSessionRangeIsEmpty() async throws {
        let repository = try SwiftDataWorkoutSessionRepository(
            inMemory: true
        )
        let date = Date(
            timeIntervalSince1970: 1_800_000_000
        )

        #expect(
            try await repository.fetchCompletedSessions(
                from: date,
                to: date
            ).isEmpty
        )
    }

    @Test("sessions can be deleted individually and all at once")
    func deletesSessions() async throws {
        let repository = try SwiftDataWorkoutSessionRepository(
            inMemory: true
        )
        let first = makeSession()
        let second = makeSession(
            id: UUID()
        )

        try await repository.saveCompleted(first)
        try await repository.saveCompleted(second)

        try await repository.deleteSession(
            id: first.id
        )

        #expect(
            try await repository.fetchSession(
                id: first.id
            ) == nil
        )
        #expect(
            try await repository.fetchSession(
                id: second.id
            ) != nil
        )

        try await repository.deleteAllSessions()

        #expect(
            try await repository.fetchSessions()
                .isEmpty
        )
    }
}

private extension SwiftDataWorkoutSessionRepositoryTests {
    func makeSession(
        id: UUID = UUID(),
        startedAt: Date = Date(
            timeIntervalSince1970: 1_800_000_000
        ),
        completed: Bool = true
    ) -> WorkoutSession {
        let endDate = completed
            ? startedAt.addingTimeInterval(600)
            : nil

        return WorkoutSession(
            id: id,
            workout: WorkoutIdentity(
                workoutID: "running",
                name: "달리기",
                category: "cardio",
                type: .dynamicWorkout
            ),
            timing: WorkoutTiming(
                startDate: startedAt,
                endDate: endDate,
                elapsedDuration: completed ? 600 : 120,
                activeDuration: completed ? 580 : 110,
                pausedDuration: completed ? 20 : 10
            ),
            route: [
                WorkoutRoutePoint(
                    timestamp: startedAt,
                    latitude: 37.5,
                    longitude: 127,
                    horizontalAccuracy: 5
                ),
                WorkoutRoutePoint(
                    timestamp: startedAt.addingTimeInterval(60),
                    latitude: 37.501,
                    longitude: 127.001,
                    horizontalAccuracy: 5
                )
            ]
        )
    }
}
