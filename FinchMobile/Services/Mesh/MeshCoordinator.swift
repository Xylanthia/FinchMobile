import Foundation
import UIKit
import Observation
import MultipeerConnectivity

/// Cooperative sensing mesh via MultipeerConnectivity (encrypted Apple stack). Shares track summaries only.
@Observable
final class MeshCoordinator: NSObject {
    var peers: [String] = []
    var isAdvertising: Bool = false
    var isBrowsing: Bool = false
    var lastMessage: String = ""
    var receivedRemoteTracks: Int = 0

    private let serviceType = "finch-mesh"
    private var peerID: MCPeerID!
    private var session: MCSession!
    private var advertiser: MCNearbyServiceAdvertiser?
    private var browser: MCNearbyServiceBrowser?
    private weak var fusion: TrackFusionEngine?
    private weak var forensic: ForensicLogger?

    override init() {
        super.init()
        peerID = MCPeerID(displayName: UIDevice.current.name)
        session = MCSession(peer: peerID, securityIdentity: nil, encryptionPreference: .required)
        session.delegate = self
    }

    func bind(fusion: TrackFusionEngine, forensic: ForensicLogger) {
        self.fusion = fusion
        self.forensic = forensic
    }

    func start() {
        stop()
        advertiser = MCNearbyServiceAdvertiser(peer: peerID, discoveryInfo: ["app": "finch"], serviceType: serviceType)
        advertiser?.delegate = self
        advertiser?.startAdvertisingPeer()
        browser = MCNearbyServiceBrowser(peer: peerID, serviceType: serviceType)
        browser?.delegate = self
        browser?.startBrowsingForPeers()
        isAdvertising = true
        isBrowsing = true
        forensic?.record(category: "mesh", summary: "Mesh started")
    }

    func stop() {
        advertiser?.stopAdvertisingPeer()
        browser?.stopBrowsingForPeers()
        session.disconnect()
        advertiser = nil
        browser = nil
        isAdvertising = false
        isBrowsing = false
        peers = []
    }

    func broadcastTracks(_ tracks: [RFTrack]) {
        guard !session.connectedPeers.isEmpty else {
            lastMessage = "No mesh peers"
            return
        }
        let payload: [[String: Any]] = tracks.prefix(40).map { t in
            var row: [String: Any] = [
                "id": t.id.uuidString,
                "name": t.displayName,
                "class": t.deviceClass.rawValue,
                "threat": t.threatScore
            ]
            if let rssi = t.rssi { row["rssi"] = rssi }
            return row
        }
        guard let data = try? JSONSerialization.data(withJSONObject: ["type": "tracks", "items": payload]) else { return }
        try? session.send(data, toPeers: session.connectedPeers, with: .reliable)
        lastMessage = "Broadcast \(payload.count) tracks → \(session.connectedPeers.count) peer(s)"
        forensic?.record(category: "mesh", summary: lastMessage)
    }
}

extension MeshCoordinator: MCSessionDelegate {
    func session(_ session: MCSession, peer peerID: MCPeerID, didChange state: MCSessionState) {
        DispatchQueue.main.async {
            self.peers = session.connectedPeers.map(\.displayName)
            self.lastMessage = "Peer \(peerID.displayName) state=\(state.rawValue)"
        }
    }

    func session(_ session: MCSession, didReceive data: Data, fromPeer peerID: MCPeerID) {
        guard
            let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let items = obj["items"] as? [[String: Any]]
        else { return }
        DispatchQueue.main.async {
            self.receivedRemoteTracks += items.count
            self.lastMessage = "Recv \(items.count) tracks from \(peerID.displayName)"
            self.forensic?.record(category: "mesh", summary: self.lastMessage)
            for item in items {
                let name = (item["name"] as? String) ?? "mesh-peer"
                let clsRaw = (item["class"] as? String) ?? "unknown"
                let cls = RFDeviceClass(rawValue: clsRaw) ?? .unknown
                _ = self.fusion?.injectSynthetic(name: "MESH:\(name)", deviceClass: cls, threatBoost: 0)
            }
        }
    }

    func session(_ session: MCSession, didReceive stream: InputStream, withName streamName: String, fromPeer peerID: MCPeerID) {}
    func session(_ session: MCSession, didStartReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, with progress: Progress) {}
    func session(_ session: MCSession, didFinishReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, at localURL: URL?, withError error: Error?) {}
}

extension MeshCoordinator: MCNearbyServiceAdvertiserDelegate {
    func advertiser(_ advertiser: MCNearbyServiceAdvertiser, didReceiveInvitationFromPeer peerID: MCPeerID, withContext context: Data?, invitationHandler: @escaping (Bool, MCSession?) -> Void) {
        invitationHandler(true, session)
    }
}

extension MeshCoordinator: MCNearbyServiceBrowserDelegate {
    func browser(_ browser: MCNearbyServiceBrowser, foundPeer peerID: MCPeerID, withDiscoveryInfo info: [String: String]?) {
        browser.invitePeer(peerID, to: session, withContext: nil, timeout: 12)
    }
    func browser(_ browser: MCNearbyServiceBrowser, lostPeer peerID: MCPeerID) {}
}
