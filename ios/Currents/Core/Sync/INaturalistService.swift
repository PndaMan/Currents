import Foundation
import CryptoKit
import AuthenticationServices
import UIKit
import Security

/// Optional, opt-in publishing of catches to iNaturalist so the wider angling
/// and science community can see them.
///
/// Flow: the user connects their own iNaturalist account once (OAuth 2 with
/// PKCE, so no client secret has to ship in the app). From then on every catch
/// — the whole existing backlog on first connect, then each new one — is
/// uploaded automatically as an iNaturalist *observation* (species, date,
/// location, photo). Nothing leaves the device until the user connects, and
/// disconnecting stops all uploads.
///
/// Setup: register an application at
/// https://www.inaturalist.org/oauth/applications with the redirect URI
/// `currents://inat-callback`, then paste its client id into
/// `INaturalistConfig.clientID`.
enum INaturalistConfig {
    /// iNaturalist OAuth application client id. Empty until the app is
    /// registered — the UI shows a "not configured" state while empty.
    static let clientID = ""
    static let redirectURI = "currents://inat-callback"
    static let callbackScheme = "currents"

    static let authorizeURL = "https://www.inaturalist.org/oauth/authorize"
    static let tokenURL = "https://www.inaturalist.org/oauth/token"
    static let apiBase = "https://api.inaturalist.org/v1"

    static var isConfigured: Bool { !clientID.isEmpty }
}

@MainActor
@Observable
final class INaturalistService: NSObject {
    /// Whether an account is connected (a token is stored).
    private(set) var isConnected: Bool = INatKeychain.token != nil
    /// Live status for the settings UI.
    private(set) var syncStatus: String?
    private(set) var isSyncing = false

    private var authSession: ASWebAuthenticationSession?

    var isConfigured: Bool { INaturalistConfig.isConfigured }

    // MARK: - Connect / disconnect

    /// Launch the OAuth flow. Resolves once a token is stored (or throws).
    func connect() async throws {
        guard INaturalistConfig.isConfigured else { throw INatError.notConfigured }

        let verifier = Self.makeCodeVerifier()
        let challenge = Self.codeChallenge(for: verifier)

        var comps = URLComponents(string: INaturalistConfig.authorizeURL)!
        comps.queryItems = [
            .init(name: "client_id", value: INaturalistConfig.clientID),
            .init(name: "redirect_uri", value: INaturalistConfig.redirectURI),
            .init(name: "response_type", value: "code"),
            .init(name: "code_challenge", value: challenge),
            .init(name: "code_challenge_method", value: "S256"),
        ]

        let callbackURL: URL = try await withCheckedThrowingContinuation { cont in
            let session = ASWebAuthenticationSession(
                url: comps.url!,
                callbackURLScheme: INaturalistConfig.callbackScheme
            ) { url, error in
                if let url {
                    cont.resume(returning: url)
                } else {
                    cont.resume(throwing: error ?? INatError.cancelled)
                }
            }
            session.presentationContextProvider = self
            session.prefersEphemeralWebBrowserSession = false
            self.authSession = session
            session.start()
        }

        guard let code = URLComponents(url: callbackURL, resolvingAgainstBaseURL: false)?
            .queryItems?.first(where: { $0.name == "code" })?.value else {
            throw INatError.noAuthCode
        }
        try await exchangeCode(code, verifier: verifier)
        isConnected = true
    }

    func disconnect() {
        INatKeychain.token = nil
        isConnected = false
        syncStatus = nil
    }

    private func exchangeCode(_ code: String, verifier: String) async throws {
        var req = URLRequest(url: URL(string: INaturalistConfig.tokenURL)!)
        req.httpMethod = "POST"
        let body = [
            "client_id": INaturalistConfig.clientID,
            "code": code,
            "redirect_uri": INaturalistConfig.redirectURI,
            "grant_type": "authorization_code",
            "code_verifier": verifier,
        ]
        req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        req.httpBody = body.map { "\($0.key)=\($0.value.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? $0.value)" }
            .joined(separator: "&").data(using: .utf8)

        let (data, resp) = try await URLSession.shared.data(for: req)
        guard (resp as? HTTPURLResponse)?.statusCode == 200,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let token = json["access_token"] as? String else {
            throw INatError.tokenExchangeFailed
        }
        INatKeychain.token = token
    }

    // MARK: - Upload

    /// Upload every catch that hasn't been shared yet, then report progress.
    /// Safe to call repeatedly — already-uploaded catches are skipped.
    func syncAll(catchRepository: CatchRepository, speciesRepository: SpeciesRepository) async {
        guard isConnected, INaturalistConfig.isConfigured, !isSyncing else { return }
        isSyncing = true
        defer { isSyncing = false }

        let pending: [Catch]
        do {
            pending = try catchRepository.fetchNotUploaded()
        } catch {
            syncStatus = "Couldn't read catches to sync."
            return
        }
        guard !pending.isEmpty else { syncStatus = "All catches shared."; return }

        var done = 0
        for record in pending {
            let species = record.speciesId.flatMap { try? speciesRepository.fetch(id: $0) }
            do {
                let obsId = try await uploadObservation(record, species: species)
                try? catchRepository.setINatObservationId(obsId, for: record.id)
                done += 1
                syncStatus = "Shared \(done)/\(pending.count) to iNaturalist…"
            } catch {
                syncStatus = "Shared \(done)/\(pending.count) — will retry the rest later."
                return
            }
        }
        syncStatus = "Shared \(done) catch\(done == 1 ? "" : "es") to iNaturalist."
    }

    /// Upload one catch if connected and not already shared. Fire-and-forget
    /// from the log-catch flow.
    func uploadIfConnected(_ record: Catch, species: Species?, catchRepository: CatchRepository) {
        guard isConnected, INaturalistConfig.isConfigured, record.inatObservationId == nil else { return }
        Task {
            if let obsId = try? await uploadObservation(record, species: species) {
                try? catchRepository.setINatObservationId(obsId, for: record.id)
            }
        }
    }

    /// POST an observation + its first photo, returning the observation id.
    private func uploadObservation(_ record: Catch, species: Species?) async throws -> String {
        guard let token = INatKeychain.token else { throw INatError.notConnected }

        let taxonId: Int?
        if let species {
            taxonId = await Self.taxonId(for: species.scientificName)
        } else {
            taxonId = nil
        }

        var observation: [String: Any] = [
            "latitude": record.latitude,
            "longitude": record.longitude,
            "observed_on_string": ISO8601DateFormatter().string(from: record.caughtAt),
        ]
        if let taxonId { observation["taxon_id"] = taxonId }
        else if let species { observation["species_guess"] = species.commonName }
        if let notes = record.notes { observation["description"] = notes }

        var req = URLRequest(url: URL(string: "\(INaturalistConfig.apiBase)/observations")!)
        req.httpMethod = "POST"
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: ["observation": observation])

        let (data, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw INatError.uploadFailed
        }
        let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        // /v1 returns {results:[{id:…}]} for creates in some versions, {id:…} in others.
        let obsId: Int? = (json?["id"] as? Int)
            ?? ((json?["results"] as? [[String: Any]])?.first?["id"] as? Int)
        guard let obsId else { throw INatError.uploadFailed }

        if let path = record.allPhotoPaths.first, let image = PhotoManager.load(path) {
            try? await uploadPhoto(image, observationId: obsId, token: token)
        }
        return String(obsId)
    }

    private func uploadPhoto(_ image: UIImage, observationId: Int, token: String) async throws {
        guard let jpeg = image.jpegData(compressionQuality: 0.85) else { return }
        let boundary = "Boundary-\(UUID().uuidString)"
        var req = URLRequest(url: URL(string: "\(INaturalistConfig.apiBase)/observation_photos")!)
        req.httpMethod = "POST"
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        var body = Data()
        func field(_ name: String, _ value: String) {
            body.append("--\(boundary)\r\n".data(using: .utf8)!)
            body.append("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n".data(using: .utf8)!)
            body.append("\(value)\r\n".data(using: .utf8)!)
        }
        field("observation_photo[observation_id]", String(observationId))
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"file\"; filename=\"catch.jpg\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: image/jpeg\r\n\r\n".data(using: .utf8)!)
        body.append(jpeg)
        body.append("\r\n--\(boundary)--\r\n".data(using: .utf8)!)
        req.httpBody = body

        _ = try? await URLSession.shared.data(for: req)
    }

    /// Resolve a scientific name to an iNaturalist taxon id (best match).
    private static func taxonId(for scientificName: String) async -> Int? {
        guard var comps = URLComponents(string: "\(INaturalistConfig.apiBase)/taxa") else { return nil }
        comps.queryItems = [.init(name: "q", value: scientificName), .init(name: "per_page", value: "1")]
        guard let url = comps.url,
              let (data, _) = try? await URLSession.shared.data(from: url),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let results = json["results"] as? [[String: Any]] else { return nil }
        return results.first?["id"] as? Int
    }

    // MARK: - PKCE helpers

    private static func makeCodeVerifier() -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return Data(bytes).base64URLEncoded()
    }

    private static func codeChallenge(for verifier: String) -> String {
        let hash = SHA256.hash(data: Data(verifier.utf8))
        return Data(hash).base64URLEncoded()
    }
}

extension INaturalistService: ASWebAuthenticationPresentationContextProviding {
    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        UIApplication.shared.connectedScenes
            .compactMap { ($0 as? UIWindowScene)?.keyWindow }
            .first ?? ASPresentationAnchor()
    }
}

enum INatError: LocalizedError {
    case notConfigured, cancelled, noAuthCode, tokenExchangeFailed, notConnected, uploadFailed

    var errorDescription: String? {
        switch self {
        case .notConfigured: "iNaturalist isn't set up in this build yet."
        case .cancelled: "Connection cancelled."
        case .noAuthCode: "iNaturalist didn't return an authorization code."
        case .tokenExchangeFailed: "Couldn't complete the iNaturalist sign-in."
        case .notConnected: "Connect your iNaturalist account first."
        case .uploadFailed: "iNaturalist upload failed."
        }
    }
}

private extension Data {
    func base64URLEncoded() -> String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}

/// Minimal Keychain wrapper for the OAuth token.
enum INatKeychain {
    private static let account = "inaturalist_access_token"

    static var token: String? {
        get {
            let query: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrAccount as String: account,
                kSecReturnData as String: true,
                kSecMatchLimit as String: kSecMatchLimitOne,
            ]
            var item: CFTypeRef?
            guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
                  let data = item as? Data else { return nil }
            return String(data: data, encoding: .utf8)
        }
        set {
            let base: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrAccount as String: account,
            ]
            SecItemDelete(base as CFDictionary)
            guard let newValue, let data = newValue.data(using: .utf8) else { return }
            var add = base
            add[kSecValueData as String] = data
            SecItemAdd(add as CFDictionary, nil)
        }
    }
}
