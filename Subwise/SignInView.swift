import AuthenticationServices
import SwiftUI

struct SignInView: View {
    @Environment(AccountSession.self) private var account
    var body: some View {
        VStack(alignment: .leading, spacing: 28) {
            Spacer()
            Image(systemName: "checkmark.seal.fill").font(.system(size: 54)).foregroundStyle(Theme.green)
            VStack(alignment: .leading, spacing: 10) {
                Text("Welcome to Subwise").font(.largeTitle.bold()).fontWidth(.expanded)
                Text("Save your subscriptions securely across devices, or continue privately on this iPhone.").font(.title3).foregroundStyle(.secondary)
            }
            Spacer()
            if case .failed(let message) = account.state { Label(message, systemImage: "exclamationmark.triangle.fill").font(.footnote).foregroundStyle(.red) }
            SignInWithAppleButton(.continue) { request in
                request.requestedScopes = [.fullName, .email]
            } onCompletion: { result in
                switch result {
                case .success(let authorization):
                    guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential else { return }
                    Task { await account.authenticate(credential: credential) }
                case .failure(let error):
                    if (error as? ASAuthorizationError)?.code != .canceled { account.state = .failed(error.localizedDescription) }
                }
            }
            .signInWithAppleButtonStyle(.black)
            .frame(height: 52)
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .disabled(account.state == .authenticating)
            Button("Continue on this device") { account.continueOffline() }.font(.headline).frame(maxWidth: .infinity, minHeight: 48)
            #if DEBUG
            Button("Enter internal development mode", systemImage: "hammer.fill") { account.continueAsDeveloper() }
                .buttonStyle(.bordered)
                .frame(maxWidth: .infinity)
                .accessibilityHint("Uses local provider simulators and never sends credentials")
            #endif
            Text("Offline mode keeps data on this device. Bank sync, household invitations, and the Savings Agent require an account.").font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)
        }.padding(24).background(Color(.systemBackground))
    }
}
