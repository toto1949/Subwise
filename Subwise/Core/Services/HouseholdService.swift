import Foundation

nonisolated struct HouseholdDTO: Decodable, Sendable {
    let id: UUID
    let name: String
    let members: [Member]
    nonisolated struct Member: Decodable, Sendable { let id: UUID; let displayName: String; let sharingMode: String }
}
nonisolated private struct CreateHouseholdRequest: Encodable { let name: String }
nonisolated private struct InviteRequest: Encodable { let email: String; let displayName: String; let sharingMode: String }

actor HouseholdService {
    static let shared = HouseholdService()
    private let api: APIClient
    init(api: APIClient = .shared) { self.api = api }

    func current() async throws -> HouseholdDTO { try await api.send(Endpoint<HouseholdDTO>(path: "households/current")) }

    func invite(email: String, name: String, sharingMode: String) async throws {
        let household: HouseholdDTO
        do { household = try await current() }
        catch {
            let body = try await api.encode(CreateHouseholdRequest(name: "My Household"))
            household = try await api.send(Endpoint<HouseholdDTO>(path: "households", method: .post, body: body, idempotencyKey: UUID().uuidString))
        }
        let body = try await api.encode(InviteRequest(email: email, displayName: name, sharingMode: sharingMode))
        _ = try await api.send(Endpoint<HouseholdDTO.Member>(path: "households/\(household.id)/invitations", method: .post, body: body, idempotencyKey: UUID().uuidString))
    }
}
