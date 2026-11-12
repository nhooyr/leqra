import Foundation

public enum NativeRoomEvent {
    case chat(ChatPacket)
    case queue(QueuePacket)
    case roomRenamed(RoomRename)
    case pilotRenamed(PilotRename)
    case notice(ServerNotice)
    case reconnecting(attempt: Int)
}

public enum ChatChannel: String, Codable, CaseIterable, Sendable { case room, opponent }

public struct NativePublicLeader: Codable, Identifiable, Equatable, Sendable {
    public let id: Int
    public let name: String
    public let score: Int
    public let bot: Bool
    public let colorIndex: Int
    public let rank: Int
    public let team: Int?
}

public struct NativePublicStatus: Decodable, Sendable {
    public let players: Int
    public let tankCount: Int
    public let capacity: Int
    public let leaders: [NativePublicLeader]
    public var latencyMilliseconds: Double = 0
    private enum CodingKeys: String, CodingKey { case players, tankCount, capacity, leaders }
}

public struct NativeChatMessage: Codable, Identifiable, Equatable, Sendable {
    public let id: UInt64
    public let member: UInt64
    public let name: String
    public let text: String
    public let spectating: Bool
    public let team: Int
    public let at: Int64
}

public struct ChatPacket: Decodable, Sendable {
    public let room: String
    public let channel: ChatChannel
    public let messages: [NativeChatMessage]
    public let isHistory: Bool
    private enum CodingKeys: String, CodingKey { case type, room, channel, message, messages }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        room = try c.decode(String.self, forKey: .room)
        channel = try c.decodeIfPresent(ChatChannel.self, forKey: .channel) ?? .room
        isHistory = try c.decode(String.self, forKey: .type) == "chat_history"
        if isHistory { messages = try c.decodeIfPresent([NativeChatMessage].self, forKey: .messages) ?? [] }
        else { messages = [try c.decode(NativeChatMessage.self, forKey: .message)] }
    }
}

public struct NativeQueueDefinition: Codable, Identifiable, Equatable, Sendable {
    public var id: String { key }
    public let key: String
    public let name: String
    public let mode: String
    public let teamSize: Int
    public let players: Int
    public let map: String
    public let cols: Int
    public let rows: Int
    public let target: Int
    public let seconds: Int
}

public struct NativeQueueListing: Codable, Identifiable, Equatable, Sendable {
    public var id: String { definition.key }
    public let definition: NativeQueueDefinition
    public let waitingPlayers: Int
    public let waitingParties: Int
}

public struct NativeQueueMember: Codable, Identifiable, Equatable, Sendable {
    public var id: UInt64 { member }
    public let member: UInt64
    public let name: String
    public let kind: String
    public let controller: UInt64
    public let accepted: Bool
}

public struct NativeQueueState: Codable, Identifiable, Equatable, Sendable {
    public let id: UInt64
    public let key: String
    public let name: String
    public let stage: String
    public let players: Int
    public let required: Int
    public let members: [NativeQueueMember]
    public let since: Int64
}

public struct NativeMatchmakingInfo: Codable, Equatable, Sendable {
    public let queue: String
    public let name: String
    public let locked: Bool
}

public struct QueuePacket: Decodable, Sendable {
    public let type: String
    public let queues: [NativeQueueListing]
    public let queue: NativeQueueState?
    public let queueId: UInt64?
    public let message: String?
    public let capacityBlocked: Bool
    private enum CodingKeys: String, CodingKey { case type, queues, queue, queueId, message, capacityBlocked }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        type = try c.decode(String.self, forKey: .type)
        queues = try c.decodeIfPresent([NativeQueueListing].self, forKey: .queues) ?? []
        queue = try c.decodeIfPresent(NativeQueueState.self, forKey: .queue)
        queueId = try c.decodeIfPresent(UInt64.self, forKey: .queueId)
        message = try c.decodeIfPresent(String.self, forKey: .message)
        capacityBlocked = try c.decodeIfPresent(Bool.self, forKey: .capacityBlocked) ?? false
    }
}

public struct RoomRename: Decodable, Sendable {
    public let old: String
    public let room: String
    public let unchanged: Bool?
}

public struct PilotRename: Decodable, Sendable {
    public let type: String
    public let id: Int?
    public let seat: Int?
    public let name: String?
    public let requestId: UInt64?
    public let message: String?
    public let member: UInt64?
    public let code: String?
    public let conflicts: [CallsignConflict]?
}

public struct CallsignConflict: Decodable, Equatable, Sendable {
    public let seat: Int
    public let name: String
}

public struct CallsignAvailability: Decodable, Equatable, Sendable {
    public let seat: Int
    public let name: String
    public let available: Bool
}

public struct ServerNotice: Decodable, Sendable {
    public let type: String
    public let code: String?
    public let action: String?
    public let channel: String?
    public let message: String?
    public let room: String?
    public let id: Int?
    public let conflicts: [CallsignConflict]?
    public let seat: Int?
}

public struct NativeMatchPlayer: Codable, Identifiable, Equatable, Sendable {
    public let id: Int
    public let member: UInt64
    public let controllerMember: UInt64?
    public let seat: Int
    public let name: String
    public let color: String
    public let team: Int
    public let score: Int
    public let kind: String
    public let eliminations: Int
    public let deaths: Int
    public let selfDestructs: Int
    public let teamKills: Int
    public let captures: Int
    public let flagReturns: Int
    public let hillSeconds: Double
    public let active: Bool
    public let winner: Bool
    public let mixedTeams: Bool
}

public struct NativeMatchReport: Codable, Equatable, Sendable {
    public let id: String?
    public let survival: ArenaSurvival?
    public let mode: String
    public let duration: Double
    public let rounds: Int
    public let players: [NativeMatchPlayer]
    public let limited: Bool
}

/// Local presets contain only roster configuration, never remote credentials.
public struct NativeSeatSpec: Codable, Equatable, Sendable {
    public var kind: String
    public var name: String
    public var difficulty: String
    public var team: Int
    public var colorIndex: Int?
    public var spectating: Bool
    public init(kind: String, name: String, difficulty: String = "normal", team: Int = 0,
                colorIndex: Int? = nil, spectating: Bool = false) {
        self.kind = kind; self.name = name; self.difficulty = difficulty
        self.team = team; self.colorIndex = colorIndex; self.spectating = spectating
    }
}

/// Every action below maps directly to an existing Go clientMessage command.
public enum NativeRoomCommand {
    case ready(Bool), start, lobby, rematch, queueInfo, returnParty, unshare
    case add(kind: String, name: String, difficulty: String = "normal", team: Int? = nil)
    case configure(target: Int, member: UInt64, name: String? = nil, difficulty: String? = nil, team: Int? = nil)
    case paint(target: Int? = nil, member: UInt64? = nil, colorIndex: Int)
    case kick(target: Int, member: UInt64)
    case spectate(Bool, target: Int? = nil, member: UInt64? = nil)
    case swap(target: Int, member: UInt64, spectator: Int, spectatorMember: UInt64)
    case rename(String), renameRoom(String)
    case renameLocal(target: Int, member: UInt64, name: String)
    case rules(RoomRules), preset(rules: RoomRules, roster: [NativeSeatSpec])
    case publicInfinity(Bool), startPublicInfinity
    case restartWave(generation: Int, wave: Int)
    case queueJoin(String), queueAccept(UInt64), queueCancel(UInt64)
    case chat(String, channel: ChatChannel = .room)

    public var payload: [String: Any] {
        switch self {
        case .ready(let ready): return ["type": "ready", "ready": ready]
        case .start: return ["type": "start"]
        case .lobby: return ["type": "lobby"]
        case .rematch: return ["type": "rematch"]
        case .queueInfo: return ["type": "queue_info"]
        case .returnParty: return ["type": "return_party"]
        case .unshare: return ["type": "unshare"]
        case .add(let kind, let name, let difficulty, let team):
            var v: [String: Any] = ["type": "add", "kind": kind, "name": name]
            if kind == "bot" { v["difficulty"] = difficulty }
            v["team"] = team
            return v
        case .configure(let target, let member, let name, let difficulty, let team):
            var v: [String: Any] = ["type": "configure", "target": target, "member": member]
            v["name"] = name; v["difficulty"] = difficulty; v["team"] = team
            return v
        case .paint(let target, let member, let color):
            var v: [String: Any] = ["type": "paint", "colorIndex": color]
            v["target"] = target; v["member"] = member
            return v
        case .kick(let target, let member): return ["type": "kick", "target": target, "member": member]
        case .spectate(let watching, let target, let member):
            var v: [String: Any] = ["type": "spectate", "spectating": watching]
            v["target"] = target; v["member"] = member
            return v
        case .swap(let target, let member, let spectator, let spectatorMember):
            return ["type": "swap", "target": target, "member": member, "spectator": spectator, "spectatorMember": spectatorMember]
        case .rename(let name): return ["type": "rename", "name": name]
        case .renameLocal(let target, let member, let name): return ["type": "rename_local", "target": target, "member": member, "name": name]
        case .renameRoom(let code): return ["type": "rename_room", "code": code]
        case .rules(let rules): return rules.command()
        case .preset(let rules, let roster):
            var v = rules.command(); v["type"] = "preset"
            if let data = try? JSONEncoder().encode(roster), let rows = try? JSONSerialization.jsonObject(with: data) { v["roster"] = rows }
            return v
        case .publicInfinity(let enabled): return ["type": "select_public_infinity", "enabled": enabled]
        case .startPublicInfinity: return ["type": "start_public_infinity"]
        case .restartWave(let generation, let wave): return ["type": "restart_wave", "generation": generation, "wave": wave]
        case .queueJoin(let key): return ["type": "queue_join", "queue": key]
        case .queueAccept(let id): return ["type": "queue_accept", "queueId": id, "ready": true]
        case .queueCancel(let id): return ["type": "queue_cancel", "queueId": id]
        case .chat(let text, let channel): return ["type": "chat", "channel": channel.rawValue, "text": text]
        }
    }
}

@MainActor public extension NetworkClient {
    func send(_ command: NativeRoomCommand) { sendCommand(command.payload) }
}
