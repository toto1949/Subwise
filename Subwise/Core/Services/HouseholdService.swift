import Foundation

nonisolated struct HouseholdDTO: Decodable, Sendable {
    let id: UUID
    let name: String
    let members: [Member]

    nonisolated struct Member: Decodable, Sendable {
        let id: UUID
        let displayName: String
        let sharingMode: String
        let userId: UUID?
        let invitedEmail: String?
    }
}

nonisolated struct HouseholdInvitationResult: Decodable, Sendable {
    let member: HouseholdDTO.Member
    let inviteURL: URL
    let delivery: String
    var wasEmailed: Bool { delivery == "email_sent" }
}

nonisolated struct HouseholdInvitationPreview: Decodable, Sendable {
    let householdName: String
    let inviterName: String
    let invitedName: String
    let expiresAt: Date
}

nonisolated private struct CreateHouseholdRequest: Encodable { let name: String }
nonisolated private struct InviteRequest: Encodable { let email: String; let displayName: String; let sharingMode: String }

actor HouseholdService {
    static let shared = HouseholdService()
    private let api: APIClient
    init(api: APIClient = .shared) { self.api = api }

    func current() async throws -> HouseholdDTO {
        try await api.send(Endpoint<HouseholdDTO>(path: "households/current"))
    }

    func invite(email: String, name: String, sharingMode: String) async throws -> HouseholdInvitationResult {
        let household: HouseholdDTO
        do {
            household = try await current()
        } catch APIError.server(let code, _, _) where code == "HOUSEHOLD_NOT_FOUND" {
            let body = try await api.encode(CreateHouseholdRequest(name: "My Household"))
            household = try await api.send(Endpoint<HouseholdDTO>(path: "households", method: .post, body: body, idempotencyKey: UUID().uuidString))
        }
        let body = try await api.encode(InviteRequest(email: email, displayName: name, sharingMode: sharingMode))
        return try await api.send(Endpoint<HouseholdInvitationResult>(path: "households/\(household.id)/invitations", method: .post, body: body, idempotencyKey: UUID().uuidString))
    }

    func invitationPreview(token: String) async throws -> HouseholdInvitationPreview {
        try await api.send(Endpoint<HouseholdInvitationPreview>(path: "household-invitations/\(token)", requiresAuthentication: false))
    }

    func acceptInvitation(token: String) async throws -> HouseholdDTO {
        try await api.send(Endpoint<HouseholdDTO>(path: "household-invitations/\(token)/accept", method: .post, idempotencyKey: token))
    }
}
