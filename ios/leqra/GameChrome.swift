import SwiftUI
import leqraCore

struct GameHeader: View {
    @ObservedObject var session: GameSession
    var landscape: Bool
    var availableWidth: CGFloat
    var showcase = false
    var embeddedStatus = false
    var statusPreview = false
    private var compact: Bool {
        availableWidth < 375 || (availableWidth < 500 && session.room != nil && !showcase)
            || embeddedStatus && availableWidth < 700
    }
    var body: some View {
        HStack(spacing: compact ? 4 : 8) {
            HStack(spacing: compact ? 4 : 8) {
                HStack(spacing: 0) {
                    if !compact {
                        Image("BrandIcon").renderingMode(.original).resizable().scaledToFit()
                            .frame(width: 36, height: 36).accessibilityHidden(true)
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        Text("leqra").font(.system(size: 17, weight: .black)).foregroundStyle(WebStyle.text)
                            .accessibilityIdentifier(showcase ? "showcaseBrand" : "brand")
                        if !landscape {
                            Text("TANK ARENA").font(WebStyle.mono()).foregroundStyle(WebStyle.muted)
                        }
                    }.fixedSize(horizontal: true, vertical: false)
                }
                if showcase {
                    versionBadge
                } else {
                    Link(destination: URL(string: "https://github.com/nhooyr/leqra")!) { versionBadge }
                        .accessibilityLabel("View leqra on GitHub")
                }
            }
            if embeddedStatus {
                ArenaStatusBar(
                    session: session, preview: statusPreview,
                    showcase: showcase ? session.showcaseFrame : nil,
                    embedded: true, compact: compact
                ).layoutPriority(1)
            }
            Spacer(minLength: 3)
            if embeddedStatus && availableWidth < 600 {
                Menu {
                    if let room = session.room, !showcase {
                        Button("Room " + room.code) {
                            if session.screen == .playing { session.setPaused(true) }
                        }
                    }
                    Button(session.soundEnabled ? "Mute sound" : "Unmute sound") {
                        session.soundEnabled.toggle()
                        session.applyAudioSetting(preview: .unmute)
                    }
                    Button(session.fullscreen ? "Exit fullscreen" : "Enter fullscreen") {
                        session.fullscreen.toggle()
                    }
                    if !showcase { Button("Open sidebar") { session.showSidebar = true } }
                } label: {
                    Image(systemName: "ellipsis").frame(width: 36, height: 36)
                }.accessibilityLabel("More game controls").foregroundStyle(WebStyle.accent)
                    .background(WebStyle.surface, in: RoundedRectangle(cornerRadius: 8))
            } else {
                if let room = session.room, !showcase {
                    Button("ROOM") { if session.screen == .playing { session.setPaused(true) } }
                        .font(WebStyle.mono(10, weight: .bold)).foregroundStyle(WebStyle.accent).padding(6)
                        .overlay(
                            RoundedRectangle(cornerRadius: 4).stroke(
                                WebStyle.accent.opacity(0.35), lineWidth: 1
                            )
                            .allowsHitTesting(false)
                        )
                        .accessibilityLabel("Room " + room.code)
                }
                WebIconButton(
                    symbol: session.soundEnabled ? "speaker.wave.2" : "speaker.slash",
                    label: session.soundEnabled ? "Mute sound" : "Unmute sound", active: session.soundEnabled
                ) {
                    guard !showcase else { return }
                    session.soundEnabled.toggle()
                    session.applyAudioSetting(preview: .unmute)
                }
                if !NativePlatform.isDesktop {
                    WebIconButton(
                        symbol: "viewfinder",
                        label: session.fullscreen ? "Exit fullscreen" : "Enter fullscreen",
                        active: session.fullscreen
                    ) { if !showcase { session.fullscreen.toggle() } }
                }
                if !showcase && (session.readyRoom || session.screen == .playing) {
                    WebIconButton(symbol: "rectangle.rightthird.inset.filled", label: "Open sidebar") {
                        session.showSidebar = true
                    }
                }
            }
            if showcase || session.screen == .playing {
                WebIconButton(symbol: "pause", label: "Pause game") {
                    if !showcase { session.setPaused(true) }
                }.accessibilityIdentifier("pauseGame")
            } else {
                WebIconButton(symbol: "slider.horizontal.3", label: "Controls") {
                    session.showControls = true
                }
            }
        }.buttonStyle(.plain)
            .frame(minHeight: NativePlatform.isDesktop ? 44 : nil)
            .padding(.horizontal, 4).padding(.bottom, landscape ? 5 : 10)
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier(showcase ? "showcaseHeader" : "gameHeader")
    }
    private var versionBadge: some View {
        ViewThatFits(in: .horizontal) {
            if !embeddedStatus || !compact {
                HStack(spacing: 4) {
                    GitHubMark().fill(WebStyle.text).frame(width: 17, height: 17)
                    Text(NetworkClient.supportedVersion).font(WebStyle.mono()).fixedSize()
                }
            }
            GitHubMark().fill(WebStyle.text).frame(width: 17, height: 17)
        }.foregroundStyle(WebStyle.muted).padding(.horizontal, 5).frame(minHeight: 32)
            .background(WebStyle.surface, in: RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8).stroke(WebStyle.border, lineWidth: 1).allowsHitTesting(
                    false))
    }
}

struct ArenaStatusBar: View {
    @ObservedObject var session: GameSession
    var preview = false
    var showcase: ShowcaseScene?
    var atBottom = false
    var embedded = false
    var compact = false
    private var infinity: Bool {
        showcase != nil
            || (preview
                ? (session.room?.infinityPublic ?? session.publicInfinitySelected)
                    || session.effectiveRules.infinity : session.isInfinity)
    }
    private var showcasePilot: ArenaTank? {
        showcase.flatMap { frame in frame.snapshot.tanks.first { $0.id == frame.localID } }
    }
    private var showcaseRank: Int? {
        guard let showcase else { return nil }
        return showcase.snapshot.leaderboard.firstIndex { $0.id == showcase.localID }.map { $0 + 1 }
    }
    private var performance: String {
        guard let showcase else { return session.performanceReadout(preview: preview) }
        return "fps: \(showcase.fps ?? 120), ping: \(showcase.ping ?? 8) ms"
    }
    var body: some View {
        HStack(spacing: 6) {
            if embedded {
                VStack(alignment: .leading, spacing: 2) {
                    identity
                    if infinity { infinityStatus } else { finiteStatus }
                }
            } else {
                identity
                if infinity { infinityStatus } else { finiteStatus }
            }
            if infinity { leaderboard }
        }.foregroundStyle(WebStyle.text).padding(.horizontal, embedded ? 4 : 12)
            .padding(.vertical, embedded ? 0 : 8)
            .frame(minHeight: embedded ? nil : preview || !infinity ? 52 : 39)
            .background(embedded ? Color.clear : WebStyle.surface)
            .overlay(alignment: atBottom ? .top : .bottom) {
                if !embedded { WebStyle.border.frame(height: 1).allowsHitTesting(false) }
            }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier(showcase == nil ? "arenaStatusBar" : "showcaseStatusBar")
    }
    private var identity: some View {
        VStack(alignment: .leading, spacing: 3) {
            if !title.isEmpty {
                HStack(spacing: 6) {
                    Circle().fill(WebStyle.accent).frame(width: 6, height: 6)
                    Text(title.uppercased()).font(WebStyle.mono()).fixedSize(
                        horizontal: false, vertical: true
                    )
                    .accessibilityIdentifier(showcase == nil ? "arenaTitle" : "showcaseTitle")
                }
            }
            if let count = onlineCount {
                Text("\(count) online").font(WebStyle.mono()).foregroundStyle(WebStyle.muted)
            } else if !infinity && session.showFPS {
                Text(performance).font(WebStyle.mono()).foregroundStyle(WebStyle.accent)
            }
        }.frame(maxWidth: embedded ? nil : .infinity, alignment: .leading)
    }
    private var infinityStatus: some View {
        VStack(alignment: embedded ? .leading : .center, spacing: 2) {
            if session.showFPS { Text(performance).foregroundStyle(WebStyle.accent) }
            if session.spectating && !preview && showcase == nil {
                Text(session.spectatorFollowingLabel).foregroundStyle(WebStyle.soft)
                    .fixedSize(horizontal: false, vertical: true).frame(minHeight: 24)
                    .accessibilityIdentifier("spectatorFollowing")
            } else {
                Text(
                    "score: \(showcasePilot?.score ?? (preview ? 0 : session.score)), rank: #\(showcaseRank ?? (preview ? 0 : session.localTank?.rank ?? 0))"
                ).foregroundStyle(WebStyle.paint(showcasePilot?.colorIndex ?? session.colorIndex))
                    .accessibilityIdentifier("gameScore")
            }
        }.font(WebStyle.mono()).frame(maxWidth: embedded ? nil : .infinity)
    }
    private var finiteStatus: some View {
        HStack(spacing: 6) {
            HStack(spacing: 5) {
                ForEach(scoreSides.prefix(8)) { entry in
                    HStack(spacing: 2) {
                        RoundedRectangle(cornerRadius: 1).fill(WebStyle.paint(entry.colorIndex)).frame(
                            width: 5, height: 5)
                        Text("\(entry.score)")
                    }
                }
            }.accessibilityIdentifier("gameScore")
            Text("ROUND \(String(format: "%02d", max(1, session.snapshot.round)))")
            Text(clock).foregroundStyle(WebStyle.accent)
        }.font(WebStyle.mono())
    }
    private var leaderboard: some View {
        Button {
            if showcase == nil { session.showScores.toggle() }
        } label: {
            if embedded && compact {
                Image(systemName: "list.number").frame(width: 24, height: 30)
            } else {
                Text("LEADERBOARD")
            }
        }.buttonStyle(.plain).accessibilityLabel("Leaderboard")
            .font(WebStyle.mono(10, weight: .semibold)).foregroundStyle(WebStyle.accent)
            .padding(.horizontal, 7).frame(minHeight: 30)
            .accessibilityIdentifier("toggleStandings")
            .background(WebStyle.sunken, in: RoundedRectangle(cornerRadius: 4))
            .overlay(
                RoundedRectangle(cornerRadius: 4).stroke(WebStyle.border, lineWidth: 1)
                    .allowsHitTesting(false))
    }
    private var title: String {
        if let showcase { return showcase.title }
        if preview {
            return infinity
                ? ((session.room?.infinityPublic ?? session.publicInfinitySelected)
                    ? "Public Infinity" : "Infinity") : ""
        }
        if infinity { return session.spectating ? "Spectating" : session.gameTitle }
        return session.snapshot.phase == "playing"
            ? "Live arena"
            : session.snapshot.phase == "countdown"
                ? "Get ready" : session.snapshot.phase == "roundOver" ? "Round complete" : "Match complete"
    }
    private var onlineCount: Int? {
        if let showcase { return showcase.snapshot.players }
        guard infinity, !session.offline else { return nil }
        if preview {
            return (session.room?.infinityPublic ?? session.publicInfinitySelected)
                ? session.publicStatus?.players : nil
        }
        return session.snapshot.players
    }
    private var clock: String {
        let seconds = max(
            0, Int(ceil(preview ? Double(session.effectiveRules.timeLimit) : session.snapshot.roundClock)))
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
    var seat = 0
    var paired = false
    var topBorder = true
    var showcase: ShowcaseScene?
    private var showcasePilot: ArenaTank? {
        showcase.flatMap { frame in frame.snapshot.tanks.first { $0.id == frame.localID } }
    }
    private var readout: PilotReadout {
        if let showcase, let tank = showcasePilot {
            return PilotReadout(
                tank: tank, snapshot: showcase.snapshot, infinity: true, paused: false, online: false)
        }
        return seat == 1 ? session.secondaryReadout : session.currentReadout
    }
    private var pilotIdentity: String {
        showcasePilot.map { $0.name + " (P1)" } ?? (seat == 1 ? session.secondaryIdentity : session.identity)
    }
    private var paint: Int {
        showcasePilot?.colorIndex ?? (seat == 1 ? session.secondaryPaint : session.colorIndex)
    }
    var body: some View {
        Group {
            if seat == 0 && session.localTank == nil && showcase == nil {
                Text("SPECTATING").font(WebStyle.mono()).foregroundStyle(WebStyle.soft).frame(
                    maxWidth: .infinity, alignment: .leading)
            } else if compact && !paired {
                HStack(spacing: 12) {
                    identity.frame(maxWidth: 190, alignment: .leading)
                    VStack(alignment: .leading, spacing: 3) {
                        ammo
                        weapon
                        readiness
                    }.frame(maxWidth: .infinity, alignment: .leading)
                }
            } else {
                VStack(alignment: .leading, spacing: 5) {
                    identity
                    HStack(alignment: .top, spacing: 10) {
                        ammo.fixedSize(horizontal: true, vertical: false)
                        weapon.frame(maxWidth: .infinity, alignment: .leading)
                    }.frame(minHeight: 30)
                    readiness
                }
            }
        }.padding(.horizontal, 13).padding(.vertical, compact ? 5 : 8)
            .frame(maxWidth: .infinity, minHeight: paired ? 75 : compact ? 54 : 97, alignment: .leading)
            .background(WebStyle.surface).overlay(alignment: .top) {
                if topBorder { WebStyle.border.frame(height: 1).allowsHitTesting(false) }
            }
    }
    private var identity: some View {
        HStack(alignment: .top, spacing: 8) {
            Text(pilotIdentity).font(
                compact ? .system(size: 11, weight: .bold) : WebStyle.mono(11, weight: .bold)
            ).foregroundStyle(WebStyle.paint(paint))
                .fixedSize(horizontal: false, vertical: true).accessibilityIdentifier(
                    seat == 1 ? "pilotIdentityP2" : "pilotIdentity")
            if readout.locked {
                Text("⚠ HOMING LOCK").font(WebStyle.mono(10, weight: .bold)).foregroundStyle(WebStyle.danger)
            }
        }
    }
    private var ammo: some View {
        HStack(spacing: 8) {
            if readout.unlimited {
                Text("∞").font(WebStyle.mono(19)).foregroundStyle(WebStyle.accent)
            } else if let seconds = readout.firingSeconds {
                VStack(alignment: .leading, spacing: 2) {
                    Text(String(format: "FIRE LEFT %.1f / 3s", ceil(seconds * 10) / 10)).font(WebStyle.mono())
                        .foregroundStyle(WebStyle.accent)
                    GeometryReader { geometry in
                        WebStyle.accent.frame(width: geometry.size.width * min(1, seconds / 3))
                    }.frame(height: 3).background(WebStyle.hover)
                }.frame(width: 112)
            } else {
                HStack(spacing: 1) {
                    ForEach(0..<min(12, readout.capacity), id: \.self) { index in
                        RoundedRectangle(cornerRadius: 2).fill(
                            index
                                < Int(
                                    ceil(
                                        Double(readout.available) / Double(readout.capacity)
                                            * Double(min(12, readout.capacity))))
                                ? WebStyle.paint(paint) : WebStyle.hover
                        ).frame(width: 4, height: 11)
                    }
                }.accessibilityLabel("\(readout.available) of \(readout.capacity) ammunition slots")
            }
        }.frame(minHeight: 15).accessibilityIdentifier(seat == 1 ? "pilotAmmoP2" : "pilotAmmo")
    }
    private var weapon: some View {
        VStack(alignment: .leading, spacing: 3) {
            if !readout.weapon.isEmpty {
                Text(readout.weapon).font(WebStyle.mono()).foregroundStyle(WebStyle.accent).fixedSize(
                    horizontal: false, vertical: true)
            }
            if !readout.buffs.isEmpty {
                Text(readout.buffs).font(WebStyle.mono()).foregroundStyle(Color(hex: "#75f0cb")).fixedSize(
                    horizontal: false, vertical: true)
            }
        }.accessibilityIdentifier(seat == 1 ? "pilotWeaponP2" : "pilotWeapon")
    }
    private var readiness: some View {
        HStack(spacing: 8) {
            Text(readout.readiness).font(WebStyle.mono()).foregroundStyle(WebStyle.soft).fixedSize(
                horizontal: false, vertical: true)
            GeometryReader { geometry in
                WebStyle.paint(paint).frame(width: geometry.size.width * readout.progress)
            }.frame(maxWidth: compact ? 100 : .infinity).frame(height: 3).background(WebStyle.hover)
        }.accessibilityIdentifier(seat == 1 ? "pilotReadinessP2" : "pilotReadiness")
    }
}

struct LocalPilotLoadouts: View {
    @ObservedObject var session: GameSession
    let landscape: Bool
    var body: some View {
        if session.secondaryLocalID != nil {
            if landscape {
                HStack(alignment: .top, spacing: 0) {
                    PilotLoadoutView(session: session, compact: true, paired: true, topBorder: false)
                    WebStyle.border.frame(width: 1)
                    PilotLoadoutView(session: session, compact: true, seat: 1, paired: true, topBorder: false)
                }.fixedSize(horizontal: false, vertical: true)
            } else {
                VStack(spacing: 0) {
                    PilotLoadoutView(session: session, compact: true, topBorder: false)
                    PilotLoadoutView(session: session, compact: true, seat: 1)
                }
            }
        } else {
            PilotLoadoutView(session: session, compact: landscape, topBorder: false)
        }
    }
}

struct ArenaStandings: View {
    @ObservedObject var session: GameSession
    var preview = false
    private var selecting: Bool { session.spectating && session.isInfinity && !preview }
    private var entries: [LeaderboardEntry] {
        if preview {
            return session.publicStatus?.leaders.map {
                LeaderboardEntry(
                    id: $0.id, name: $0.name, score: $0.score, colorIndex: $0.colorIndex, bot: $0.bot,
                    team: $0.team ?? 0, difficulty: $0.difficulty)
            } ?? []
        }
        return session.standings
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                session.showScores = false
            } label: {
                HStack {
                    Text("LEADERBOARD")
                    Spacer()
                    Image(systemName: "chevron.up")
                }.font(WebStyle.mono()).foregroundStyle(WebStyle.accent).padding(12)
            }.accessibilityIdentifier("closeStandings")
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    if entries.isEmpty {
                        Text("No tanks yet").font(.system(size: 12)).foregroundStyle(WebStyle.soft).padding(
                            12)
                    }
                    ForEach(
                        Array(entries.prefix(selecting ? entries.count : 10).enumerated()), id: \.element.id
                    ) { index, entry in
                        if selecting {
                            Button {
                                session.followTank(entry.id)
                            } label: {
                                row(entry, rank: index + 1)
                            }
                            .buttonStyle(.plain).disabled(!session.canFollowTanks || entry.id <= 0)
                            .accessibilityIdentifier("followTank_\(entry.id)")
                            .accessibilityValue(entry.id == session.followingID ? "Following" : "Follow tank")
                        } else {
                            row(entry, rank: index + 1)
                        }
                    }
                }
            }.accessibilityIdentifier("standingsScroll")
            if selecting {
                Text(session.followError.isEmpty ? "Tap a tank to follow" : session.followError)
                    .foregroundStyle(session.followError.isEmpty ? WebStyle.soft : WebStyle.danger)
                    .font(.system(size: 11)).fixedSize(horizontal: false, vertical: true).padding(10)
            }
            Text("+1 per kill, -1 per death").font(.system(size: 11)).foregroundStyle(WebStyle.soft).padding(
                10)
        }.frame(width: selecting ? 245 : 205).frame(maxHeight: 330)
            .accessibilityElement(children: .contain).accessibilityIdentifier("arenaStandings")
            .background(WebStyle.surface, in: RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8).stroke(WebStyle.edge, lineWidth: 1).allowsHitTesting(false))
    }

    private func row(_ entry: LeaderboardEntry, rank: Int) -> some View {
        let seat = preview ? nil : session.localPilotSeat(entry.id)
        return HStack(alignment: .top, spacing: 6) {
            Text("\(rank).")
            Text(entry.displayName + (seat.map { " (P\($0))" } ?? ""))
                .fontWeight(seat != nil ? .bold : .regular).fixedSize(horizontal: false, vertical: true)
            if let difficulty = entry.difficultyLabel {
                Text(difficulty).font(WebStyle.mono()).foregroundStyle(WebStyle.muted).fixedSize()
            }
            if selecting && entry.id == session.followingID {
                Image(systemName: "eye").font(.system(size: 10)).accessibilityHidden(true)
            }
            Spacer(minLength: 2)
            Text("\(entry.score)").bold().monospacedDigit()
        }.font(.system(size: 12)).foregroundStyle(WebStyle.paint(entry.colorIndex)).padding(.vertical, 5)
            .padding(.horizontal, 10)
            .frame(maxWidth: .infinity, minHeight: selecting ? 44 : 0, alignment: .leading)
            .background(
                (seat != nil || selecting && entry.id == session.followingID)
                    ? WebStyle.paint(entry.colorIndex).opacity(0.08) : .clear
            )
            .contentShape(Rectangle())
            .accessibilityElement(children: .combine)
    }
}
