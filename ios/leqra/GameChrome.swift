import SwiftUI
import leqraCore

struct GameHeader: View {
    @ObservedObject var session: GameSession
    var landscape: Bool
    var availableWidth: CGFloat
    private var compact: Bool { availableWidth < 375 || (availableWidth < 500 && session.room != nil) }
    var body: some View {
        HStack(spacing: compact ? 4 : 8) {
            HStack(spacing: compact ? 4 : 8) {
                if !compact {
                    TankMark().padding(4).background(WebStyle.accent.opacity(0.05), in: RoundedRectangle(cornerRadius: 7))
                        .overlay(RoundedRectangle(cornerRadius: 7).stroke(WebStyle.accent.opacity(0.3), lineWidth: 1).allowsHitTesting(false)).rotationEffect(.degrees(-4))
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text("leqra").font(.system(size: 17, weight: .black)).foregroundStyle(WebStyle.text)
                    if !landscape { Text("TANK ARENA").font(WebStyle.mono()).foregroundStyle(WebStyle.muted) }
                }.fixedSize(horizontal: true, vertical: false)
                Link(destination: URL(string: "https://github.com/nhooyr/leqra")!) {
                    HStack(spacing: 4) {
                        GitHubMark().fill(WebStyle.text).frame(width: 17, height: 17)
                        if !landscape { Text("v" + NetworkClient.supportedVersion).font(WebStyle.mono()).fixedSize() }
                    }.foregroundStyle(WebStyle.muted).padding(.horizontal, 5).frame(minHeight: 32)
                        .background(WebStyle.surface, in: RoundedRectangle(cornerRadius: 8))
                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(WebStyle.border, lineWidth: 1).allowsHitTesting(false))
                }.accessibilityLabel("View leqra on GitHub")
            }
            Spacer(minLength: 3)
            if let room = session.room {
                Button("ROOM") { if session.screen == .playing { session.setPaused(true) } }
                    .font(WebStyle.mono(10, weight: .bold)).foregroundStyle(WebStyle.accent).padding(6)
                    .overlay(RoundedRectangle(cornerRadius: 4).stroke(WebStyle.accent.opacity(0.35), lineWidth: 1).allowsHitTesting(false))
                    .accessibilityLabel("Room " + room.code)
            }
            if session.room != nil {
                WebIconButton(symbol: "bubble.left", label: "Chat") { session.showChat.toggle() }
            }
            WebIconButton(symbol: session.soundEnabled ? "speaker.wave.2" : "speaker.slash", label: session.soundEnabled ? "Mute sound" : "Unmute sound", active: session.soundEnabled) {
                session.soundEnabled.toggle(); session.applyAudioSetting(preview: .unmute)
            }
            WebIconButton(symbol: "viewfinder", label: session.fullscreen ? "Exit fullscreen" : "Enter fullscreen", active: session.fullscreen) { session.fullscreen.toggle() }
            if session.screen == .playing {
                WebIconButton(symbol: "pause", label: "Pause game") { session.setPaused(true) }.accessibilityIdentifier("pauseGame")
            } else {
                WebIconButton(symbol: "slider.horizontal.3", label: "Settings") { session.showSettings = true }
            }
        }.padding(.horizontal, 4).padding(.bottom, landscape ? 5 : 10)
    }
}

struct ArenaStatusBar: View {
    @ObservedObject var session: GameSession
    var preview = false
    private var infinity: Bool { preview ? (session.room?.infinityPublic ?? session.publicInfinitySelected) || session.effectiveRules.infinity : session.isInfinity }
    var body: some View {
        HStack(spacing: 6) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Circle().fill(WebStyle.accent).frame(width: 6, height: 6)
                    Text(title.uppercased()).font(WebStyle.mono()).fixedSize(horizontal: false, vertical: true)
                }
                if let count = onlineCount {
                    Text("\(count) online").font(WebStyle.mono()).foregroundStyle(WebStyle.muted)
                } else if preview && !infinity && session.showFPS {
                    Text(session.performanceReadout(preview: true)).font(WebStyle.mono()).foregroundStyle(WebStyle.accent)
                }
            }.frame(maxWidth: .infinity, alignment: .leading)
            if infinity {
                VStack(spacing: 2) {
                    if session.showFPS { Text(session.performanceReadout(preview: preview)).foregroundStyle(WebStyle.accent) }
                    Text("score: \(preview ? 0 : session.score), rank: #\(preview ? 0 : session.localTank?.rank ?? 0)")
                        .foregroundStyle(WebStyle.paint(session.colorIndex)).accessibilityIdentifier("gameScore")
                }.font(WebStyle.mono()).frame(maxWidth: .infinity)
                Button("LEADERBOARD") { session.showScores.toggle() }
                    .font(WebStyle.mono(10, weight: .semibold)).foregroundStyle(WebStyle.accent)
                    .padding(.horizontal, 7).frame(minHeight: 30)
                    .background(WebStyle.sunken, in: RoundedRectangle(cornerRadius: 4))
                    .overlay(RoundedRectangle(cornerRadius: 4).stroke(WebStyle.border, lineWidth: 1).allowsHitTesting(false))
            } else {
                HStack(spacing: 5) {
                    ForEach(scoreSides.prefix(8)) { entry in
                        HStack(spacing: 2) { RoundedRectangle(cornerRadius: 1).fill(WebStyle.paint(entry.colorIndex)).frame(width: 5, height: 5); Text("\(entry.score)") }
                    }
                }.font(WebStyle.mono()).accessibilityIdentifier("gameScore")
                Text("ROUND \(String(format: "%02d", max(1, session.snapshot.round)))").font(WebStyle.mono())
                Text(clock).font(WebStyle.mono()).foregroundStyle(WebStyle.accent)
                WebIconButton(symbol: "rectangle.rightthird.inset.filled", label: "Open sidebar") { session.showSidebar = true }
            }
        }.foregroundStyle(WebStyle.text).padding(.horizontal, 12).padding(.vertical, 8)
            // The finite preview's sidebar button establishes a 52pt row.
            // Keep that footprint when Infinity uses its shorter leaderboard.
            .frame(minHeight: preview ? 52 : 39).background(WebStyle.surface)
            .overlay(alignment: .bottom) { WebStyle.border.frame(height: 1).allowsHitTesting(false) }
    }
    private var title: String {
        if preview { return infinity ? ((session.room?.infinityPublic ?? session.publicInfinitySelected) ? "Public Infinity" : "Infinity") : "Ready room" }
        if infinity { return session.gameTitle }
        return session.snapshot.phase == "playing" ? "Live arena" : session.snapshot.phase == "countdown" ? "Get ready" : session.snapshot.phase == "roundOver" ? "Round complete" : "Match complete"
    }
    private var onlineCount: Int? {
        guard infinity, !session.offline else { return nil }
        if preview { return (session.room?.infinityPublic ?? session.publicInfinitySelected) ? session.publicStatus?.players : nil }
        return session.snapshot.players
    }
    private var clock: String {
        let seconds = max(0, Int(ceil(preview ? Double(session.effectiveRules.timeLimit) : session.snapshot.roundClock)))
        return String(format: "%02d:%02d", seconds / 60, seconds % 60)
    }
    private var scoreSides: [LeaderboardEntry] {
        guard session.effectiveRules.teamMode == "teams" else { return session.standings }
        var teams = Set<Int>()
        return session.standings.filter { entry in entry.team > 0 && teams.insert(entry.team).inserted }
    }
}

struct PilotLoadoutView: View {
    @ObservedObject var session: GameSession
    var compact = false
    private var readout: PilotReadout { session.currentReadout }
    var body: some View {
        Group {
            if session.localTank == nil {
                Text("SPECTATING").font(WebStyle.mono()).foregroundStyle(WebStyle.soft).frame(maxWidth: .infinity, alignment: .leading)
            } else if compact {
                HStack(spacing: 12) {
                    identity.frame(maxWidth: 190, alignment: .leading)
                    VStack(alignment: .leading, spacing: 3) { ammo; weapon; readiness }.frame(maxWidth: .infinity, alignment: .leading)
                }
            } else {
                VStack(alignment: .leading, spacing: 5) {
                    identity
                    HStack(alignment: .top, spacing: 10) {
                        ammo.frame(width: 60, alignment: .leading)
                        weapon.frame(maxWidth: .infinity, alignment: .leading)
                    }.frame(minHeight: 30)
                    readiness
                }
            }
        }.padding(.horizontal, 13).padding(.vertical, compact ? 5 : 8)
            .frame(maxWidth: .infinity, minHeight: compact ? 54 : 97, alignment: .leading)
            .background(WebStyle.surface).overlay(alignment: .top) { WebStyle.border.frame(height: 1).allowsHitTesting(false) }
    }
    private var identity: some View {
        HStack(alignment: .top, spacing: 8) {
            Text(session.identity).font(compact ? .system(size: 11, weight: .bold) : WebStyle.mono(11, weight: .bold)).foregroundStyle(WebStyle.paint(session.colorIndex))
                .fixedSize(horizontal: false, vertical: true).accessibilityIdentifier("pilotIdentity")
            if readout.locked { Text("⚠ HOMING LOCK").font(WebStyle.mono(10, weight: .bold)).foregroundStyle(WebStyle.danger) }
        }
    }
    private var ammo: some View {
        HStack(spacing: 8) {
            if readout.unlimited { Text("∞").font(WebStyle.mono(19)).foregroundStyle(WebStyle.accent) }
            else if let seconds = readout.firingSeconds {
                VStack(alignment: .leading, spacing: 2) {
                    Text(String(format: "FIRE LEFT %.1f / 3s", ceil(seconds * 10) / 10)).font(WebStyle.mono()).foregroundStyle(WebStyle.accent)
                    GeometryReader { geometry in WebStyle.accent.frame(width: geometry.size.width * min(1, seconds / 3)) }.frame(height: 3).background(WebStyle.hover)
                }.frame(width: 112)
            } else {
                HStack(spacing: 1) {
                    ForEach(0..<min(12, readout.capacity), id: \.self) { index in
                        RoundedRectangle(cornerRadius: 2).fill(index < Int(ceil(Double(readout.available) / Double(readout.capacity) * Double(min(12, readout.capacity)))) ? WebStyle.paint(session.colorIndex) : WebStyle.hover).frame(width: 4, height: 11)
                    }
                }.accessibilityLabel("\(readout.available) of \(readout.capacity) ammunition slots")
            }
        }.frame(minHeight: 15)
    }
    private var weapon: some View {
        VStack(alignment: .leading, spacing: 3) {
            if !readout.weapon.isEmpty { Text(readout.weapon).font(WebStyle.mono()).foregroundStyle(WebStyle.accent).fixedSize(horizontal: false, vertical: true) }
            if !readout.buffs.isEmpty { Text(readout.buffs).font(WebStyle.mono()).foregroundStyle(Color(hex: "#75f0cb")).fixedSize(horizontal: false, vertical: true) }
        }
    }
    private var readiness: some View {
        HStack(spacing: 8) {
            Text(readout.readiness).font(WebStyle.mono()).foregroundStyle(WebStyle.soft).fixedSize(horizontal: false, vertical: true)
            GeometryReader { geometry in WebStyle.paint(session.colorIndex).frame(width: geometry.size.width * readout.progress) }.frame(maxWidth: compact ? 100 : .infinity).frame(height: 3).background(WebStyle.hover)
        }
    }
}

struct ArenaStandings: View {
    @ObservedObject var session: GameSession
    var preview = false
    private var entries: [LeaderboardEntry] {
        if preview { return session.publicStatus?.leaders.map { LeaderboardEntry(id: $0.id, name: $0.name, score: $0.score, colorIndex: $0.colorIndex, bot: $0.bot, team: $0.team ?? 0) } ?? [] }
        return session.standings
    }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Button { session.showScores = false } label: { HStack { Text("LEADERBOARD"); Spacer(); Image(systemName: "chevron.up") }.font(WebStyle.mono()).foregroundStyle(WebStyle.accent).padding(12) }
                if entries.isEmpty { Text("No tanks yet").font(.system(size: 12)).foregroundStyle(WebStyle.soft).padding(12) }
                ForEach(Array(entries.prefix(10).enumerated()), id: \.element.id) { index, entry in
                    HStack(alignment: .top, spacing: 6) {
                        Text("\(index + 1).")
                        Text(entry.id == session.localID && !preview ? "\(entry.name) (P1)" : CallsignPolicy.displayName(entry.name, bot: entry.bot))
                            .fontWeight(entry.id == session.localID && !preview ? .bold : .regular).fixedSize(horizontal: false, vertical: true)
                        if entry.bot { Text("BOT").font(WebStyle.mono()).foregroundStyle(WebStyle.muted) }
                        Spacer(minLength: 2); Text("\(entry.score)").bold().monospacedDigit()
                    }.font(.system(size: 12)).foregroundStyle(WebStyle.paint(entry.colorIndex)).padding(.vertical, 5).padding(.horizontal, 10)
                        .background(entry.id == session.localID && !preview ? WebStyle.paint(entry.colorIndex).opacity(0.08) : .clear)
                        .accessibilityElement(children: .combine)
                }
                Text("+1 per kill, -1 per death").font(.system(size: 11)).foregroundStyle(WebStyle.soft).padding(10)
            }
        }.frame(width: 205).frame(maxHeight: 330).accessibilityIdentifier("arenaStandings")
            .background(WebStyle.surface, in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(WebStyle.edge, lineWidth: 1).allowsHitTesting(false))
    }
}
