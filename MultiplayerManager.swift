import Foundation
import MultipeerConnectivity
import UIKit

// Формат сообщений между устройствами
enum NetMessage: Codable {
    case hello(name: String)
    case inviteFrom(name: String)
    case accept
    case decline
    case clientHero(y: CGFloat)
    case gameState(state: NetGameState)
}

struct NetEnemy: Codable {
    var x: CGFloat
    var y: CGFloat
    var size: CGFloat
}

struct NetBullet: Codable {
    var x: CGFloat
    var y: CGFloat
    var fromClient: Bool
}

struct NetGameState: Codable {
    var hostHeroY: CGFloat
    var clientHeroY: CGFloat
    var enemies: [NetEnemy]
    var bullets: [NetBullet]
    var score: Int
    var coins: Int
    var isGameOver: Bool
}

final class MultiplayerManager: NSObject, ObservableObject {
    // Публичное состояние
    @Published var discoveredPeers: [MCPeerID] = []
    @Published var connectedPeers: [MCPeerID] = []
    @Published var incomingInvite: (peer: MCPeerID, name: String)? = nil
    @Published var isHost: Bool = false
    @Published var isSearching: Bool = false

    private var session: MCSession!
    private var advertiser: MCNearbyServiceAdvertiser?
    private var browser: MCNearbyServiceBrowser?
    private var pendingInviteHandler: ((Bool, MCSession?) -> Void)?

    private let serviceType = "cosmic-sngrv"

    override init() {
        super.init()
        let name = UIDevice.current.name
        let displayName = name.isEmpty ? "Player" : String(name.prefix(20))
        let peerID = MCPeerID(displayName: displayName)
        session = MCSession(peer: peerID, securityIdentity: nil, encryptionPreference: .required)
        session.delegate = self
    }

    func startSearch() {
        isSearching = true

        advertiser = MCNearbyServiceAdvertiser(peer: session.myPeerID, discoveryInfo: nil, serviceType: serviceType)
        advertiser?.delegate = self
        advertiser?.startAdvertisingPeer()

        browser = MCNearbyServiceBrowser(peer: session.myPeerID, serviceType: serviceType)
        browser?.delegate = self
        browser?.startBrowsingForPeers()
    }

    func stopSearch() {
        isSearching = false
        advertiser?.stopAdvertisingPeer()
        browser?.stopBrowsingForPeers()
        advertiser = nil
        browser = nil
    }

    func disconnect() {
        stopSearch()
        session.disconnect()
        DispatchQueue.main.async {
            self.discoveredPeers = []
            self.connectedPeers = []
        }
    }

    func invite(_ peer: MCPeerID) {
        guard let browser = browser else { return }
        isHost = true
        browser.invitePeer(peer, to: session, withContext: nil, timeout: 15)
    }

    func acceptInvite() {
        guard let handler = pendingInviteHandler else { return }
        handler(true, session)
        pendingInviteHandler = nil
        incomingInvite = nil
        isHost = false
    }

    func declineInvite() {
        guard let handler = pendingInviteHandler else { return }
        handler(false, nil)
        pendingInviteHandler = nil
        incomingInvite = nil
    }

    // Отправка данных (unreliable — для игровых апдейтов; reliable — для критичных)
    func send(_ message: NetMessage, reliable: Bool = false) {
        guard !session.connectedPeers.isEmpty else { return }
        guard let data = try? JSONEncoder().encode(message) else { return }
        do {
            try session.send(data, toPeers: session.connectedPeers,
                             with: reliable ? .reliable : .unreliable)
        } catch {
            print("Send error: \(error)")
        }
    }

    // Колбэк при получении данных
    var onMessage: ((NetMessage) -> Void)?

    // Колбэк при подключении/отключении
    var onConnect: (() -> Void)?
    var onDisconnect: (() -> Void)?
}

// MARK: - MCSessionDelegate
extension MultiplayerManager: MCSessionDelegate {
    func session(_ session: MCSession, peer peerID: MCPeerID, didChange state: MCSessionState) {
        DispatchQueue.main.async {
            self.connectedPeers = session.connectedPeers
            switch state {
            case .connected:
                self.onConnect?()
            case .notConnected:
                if session.connectedPeers.isEmpty {
                    self.onDisconnect?()
                }
            default: break
            }
        }
    }

    func session(_ session: MCSession, didReceive data: Data, fromPeer peerID: MCPeerID) {
        if let msg = try? JSONDecoder().decode(NetMessage.self, from: data) {
            DispatchQueue.main.async {
                self.onMessage?(msg)
            }
        }
    }

    func session(_ session: MCSession, didReceive stream: InputStream,
                 withName streamName: String, fromPeer peerID: MCPeerID) {}
    func session(_ session: MCSession, didStartReceivingResourceWithName resourceName: String,
                 fromPeer peerID: MCPeerID, with progress: Progress) {}
    func session(_ session: MCSession, didFinishReceivingResourceWithName resourceName: String,
                 fromPeer peerID: MCPeerID, at localURL: URL?, withError error: Error?) {}
}

// MARK: - MCNearbyServiceAdvertiserDelegate (приём приглашений)
extension MultiplayerManager: MCNearbyServiceAdvertiserDelegate {
    func advertiser(_ advertiser: MCNearbyServiceAdvertiser,
                    didReceiveInvitationFromPeer peerID: MCPeerID,
                    withContext context: Data?,
                    invitationHandler: @escaping (Bool, MCSession?) -> Void) {
        DispatchQueue.main.async {
            self.pendingInviteHandler = invitationHandler
            self.incomingInvite = (peerID, peerID.displayName)
        }
    }
}

// MARK: - MCNearbyServiceBrowserDelegate (поиск)
extension MultiplayerManager: MCNearbyServiceBrowserDelegate {
    func browser(_ browser: MCNearbyServiceBrowser, foundPeer peerID: MCPeerID,
                 withDiscoveryInfo info: [String : String]?) {
        DispatchQueue.main.async {
            if !self.discoveredPeers.contains(where: { $0 == peerID }) {
                self.discoveredPeers.append(peerID)
            }
        }
    }

    func browser(_ browser: MCNearbyServiceBrowser, lostPeer peerID: MCPeerID) {
        DispatchQueue.main.async {
            self.discoveredPeers.removeAll { $0 == peerID }
        }
    }
}
