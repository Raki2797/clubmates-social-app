import Foundation

@MainActor
final class VenueVotingViewModel: ObservableObject {
    @Published private(set) var venueName: String = ""
    @Published private(set) var competitions: [VenueVotingCompetition] = []
    @Published private(set) var history: [VenueVotingHistoryItem] = []
    @Published private(set) var isLoading = false
    @Published private(set) var isJoining = false
    @Published private(set) var isVoting = false
    @Published private(set) var isRestarting = false
    @Published var selectedCategory: VenueVotingCategory = .female
    @Published var errorMessage: String?

    private let api: NetworkClient
    private let realtimeDecoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = APIDateDecoding.strategy
        return decoder
    }()
    private var realtimeTask: URLSessionWebSocketTask?
    private var realtimeListenTask: Task<Void, Never>?
    private var realtimeVenueId: UUID?

    private struct VenueVotingRealtimeEvent: Decodable {
        let type: String
        let venueId: UUID?
    }

    init(api: NetworkClient = .shared) {
        self.api = api
    }

    deinit {
        realtimeListenTask?.cancel()
        realtimeTask?.cancel(with: .goingAway, reason: nil)
    }

    var selectedCompetition: VenueVotingCompetition? {
        competitions.first { $0.category == selectedCategory }
            ?? competitions.first
    }

    func load(venue: Venue) {
        Task {
            await reload(venue: venue, showLoading: true)
        }
    }

    func connectRealtime(venue: Venue) {
        guard realtimeTask == nil || realtimeVenueId != venue.id else { return }
        stopRealtime()
        realtimeVenueId = venue.id

        Task {
            do {
                let url = try await api.webSocketURL()
                let task = URLSession.shared.webSocketTask(with: url)
                realtimeTask = task
                task.resume()
                listenForRealtimeMessages(task: task, venue: venue)
            } catch {
                // Realtime is additive; normal fetches still keep the screen usable.
            }
        }
    }

    func stopRealtime() {
        realtimeListenTask?.cancel()
        realtimeListenTask = nil
        realtimeTask?.cancel(with: .goingAway, reason: nil)
        realtimeTask = nil
        realtimeVenueId = nil
    }

    func join(venue: Venue) {
        guard !isJoining else { return }

        Task {
            isJoining = true
            defer { isJoining = false }

            do {
                let response = try await api.joinVenueVoting(venueId: venue.id, category: selectedCategory)
                upsert(response.competition.competition)
                errorMessage = nil
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    func restartDemo(venue: Venue) {
        guard !isRestarting else { return }

        Task {
            isRestarting = true
            defer { isRestarting = false }

            do {
                let response = try await api.restartVenueVotingDemo(venueId: venue.id)
                competitions = response.competitions.map(\.competition).sorted { $0.category.title < $1.category.title }
                errorMessage = nil
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    func vote(entry: VenueVotingEntry) {
        guard !isVoting, let competition = selectedCompetition else { return }

        Task {
            isVoting = true
            defer { isVoting = false }

            do {
                let response = try await api.voteInVenueCompetition(
                    competitionId: competition.id,
                    entryId: entry.entryId
                )
                upsert(response.competition.competition)
                errorMessage = nil
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func upsert(_ competition: VenueVotingCompetition) {
        if let index = competitions.firstIndex(where: { $0.id == competition.id }) {
            competitions[index] = competition
        } else {
            competitions.append(competition)
            competitions.sort { $0.category.title < $1.category.title }
        }
    }

    private func reload(venue: Venue, showLoading: Bool) async {
        if showLoading {
            isLoading = true
        }
        defer {
            if showLoading {
                isLoading = false
            }
        }

        do {
            async let votingResponse = api.venueVoting(venueId: venue.id)
            async let historyResponse = api.venueVotingHistory()

            let (voting, votingHistory) = try await (votingResponse, historyResponse)
            venueName = voting.venueName
            competitions = voting.competitions.map(\.competition).sorted { $0.category.title < $1.category.title }
            history = votingHistory.history.map(\.historyItem)

            if competitions.contains(where: { $0.category == selectedCategory }) == false {
                selectedCategory = competitions.first?.category ?? .female
            }
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func listenForRealtimeMessages(task: URLSessionWebSocketTask, venue: Venue) {
        realtimeListenTask = Task { [weak self] in
            while !Task.isCancelled {
                do {
                    let message = try await task.receive()
                    await self?.handleRealtimeMessage(message, venue: venue)
                } catch {
                    return
                }
            }
        }
    }

    private func handleRealtimeMessage(_ message: URLSessionWebSocketTask.Message, venue: Venue) async {
        let data: Data?
        switch message {
        case .string(let text):
            data = text.data(using: .utf8)
        case .data(let messageData):
            data = messageData
        @unknown default:
            data = nil
        }

        guard
            let data,
            let event = try? realtimeDecoder.decode(VenueVotingRealtimeEvent.self, from: data),
            event.type == "venue_voting.updated",
            event.venueId == venue.id
        else {
            return
        }

        await reload(venue: venue, showLoading: false)
    }
}
