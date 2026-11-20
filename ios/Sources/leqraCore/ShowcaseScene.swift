import Foundation

/// The single frozen scene exported by scripts/render-showcase.cjs for every renderer.
/// Extra render history stays outside the live protocol model.
public struct ShowcaseScene: Decodable, Sendable {
    public struct ProjectileHistory: Decodable, Sendable {
        public let id: Int
        public let trail: [BeamPoint]
        public let target: Int?
        private enum CodingKeys: String, CodingKey { case id, trail, target }
        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            id = try c.decode(Int.self, forKey: .id)
            trail = try c.decodeIfPresent([BeamPoint].self, forKey: .trail) ?? []
            target = try c.decodeIfPresent(Int.self, forKey: .target)
        }
    }
    public struct EffectHistory: Decodable, Sendable {
        public let id: Int
        public let ageMilliseconds: Double
        public let outline: [BeamPoint]
        private enum CodingKeys: String, CodingKey { case id, showcaseAge, outline }
        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            id = try c.decode(Int.self, forKey: .id)
            ageMilliseconds = try c.decodeIfPresent(Double.self, forKey: .showcaseAge) ?? 0
            outline = try c.decodeIfPresent([BeamPoint].self, forKey: .outline) ?? []
        }
    }
    public let snapshot: ArenaSnapshot
    public let seed: UInt32
    public let timeMilliseconds: Double
    public let localID: Int
    public let fps: Int?
    public let ping: Int?
    public let title: String
    public let projectiles: [ProjectileHistory]
    public let effects: [EffectHistory]
    public var time: Double { timeMilliseconds / 1000 }
    public var maze: InfiniteMaze { InfiniteMaze(seed: seed) }

    private enum CodingKeys: String, CodingKey {
        case seed, time, localID, fps, ping, title, bullets, effects
    }
    public init(from decoder: Decoder) throws {
        var frame = try ArenaSnapshot(from: decoder)
        let c = try decoder.container(keyedBy: CodingKeys.self)
        seed = try c.decode(UInt32.self, forKey: .seed)
        timeMilliseconds = try c.decode(Double.self, forKey: .time)
        localID = try c.decode(Int.self, forKey: .localID)
        fps = try c.decodeIfPresent(Int.self, forKey: .fps)
        ping = try c.decodeIfPresent(Int.self, forKey: .ping)
        title = try c.decodeIfPresent(String.self, forKey: .title) ?? "Public Infinity"
        projectiles = try c.decode([ProjectileHistory].self, forKey: .bullets)
        effects = try c.decode([EffectHistory].self, forKey: .effects)
        // Live native pilots start at 1, but this shared frozen fixture starts
        // at 0. Preserve "no target" instead of interpreting null as the hero.
        let targets = Dictionary(uniqueKeysWithValues: projectiles.map { ($0.id, $0.target ?? -1) })
        for index in frame.bullets.indices {
            frame.bullets[index].target = targets[frame.bullets[index].id] ?? -1
        }
        snapshot = frame
    }

    private struct Resource: Decodable {
        let wide: ShowcaseScene
        let portrait: ShowcaseScene?
        enum CodingKeys: String, CodingKey { case portrait }
        init(from decoder: Decoder) throws {
            wide = try ShowcaseScene(from: decoder)
            portrait = try decoder.container(keyedBy: CodingKeys.self).decodeIfPresent(
                ShowcaseScene.self, forKey: .portrait)
        }
    }

    /// Orientation selects a canonical authored scene; it never crops or
    /// rewrites the other variant's simulation entities.
    public static func decode(_ data: Data, portrait: Bool = false) throws -> ShowcaseScene {
        let resource = try JSONDecoder().decode(Resource.self, from: data)
        if !portrait { return resource.wide }
        guard let selected = resource.portrait else {
            throw DecodingError.keyNotFound(
                Resource.CodingKeys.portrait,
                DecodingError.Context(
                    codingPath: [], debugDescription: "The portrait Showcase scene is missing."))
        }
        return selected
    }

    public static func load(portrait: Bool = false) throws -> ShowcaseScene {
        guard let url = Bundle.module.url(forResource: "showcase", withExtension: "json") else {
            throw CocoaError(.fileNoSuchFile)
        }
        return try decode(Data(contentsOf: url), portrait: portrait)
    }
}
