import SwiftUI
import leqraCore

struct ContentView: View {
    @ObservedObject var session: GameSession
    @Environment(\.scenePhase) private var scenePhase
    var body: some View {
        GeometryReader { geometry in
            let landscape = geometry.size.width > geometry.size.height
            ZStack {
                WebStyle.page.ignoresSafeArea()
                VStack(spacing: 0) {
                    GameHeader(session: session, landscape: landscape, availableWidth: geometry.size.width)
                    if session.readyRoom { readyRoom(landscape: landscape) }
                    else if session.screen == .connecting { connecting }
                    else { game(landscape: landscape) }
                }.padding(.horizontal, session.screen == .playing && session.isInfinity ? 0 : 9)
                    .padding(.top, landscape ? 5 : 9).padding(.bottom, session.screen == .playing && session.isInfinity ? 0 : 8)
                    .allowsHitTesting(!session.paused && !session.showRules && !session.showControls && !session.showSettings && !session.showJoin && !session.showPresets && !session.showQueues && !session.showSidebar)
                if session.paused && session.screen == .playing { PauseCard(session: session, landscape: landscape) }
                if session.showSidebar { SidebarPanel(session: session) }
                if session.showPresets { PresetsPanel(session: session) }
                if session.showQueues { QueuePanel(session: session) }
                if session.showJoin { JoinRoomPanel(session: session) }
                if session.showRules { RulesEditor(session: session) }
                if session.showControls { ControlsPanel(session: session) }
                if session.showSettings { NativeSettings(session: session) }
                if session.showChat { VStack { Spacer(); HStack { Spacer(); ChatPanel(session: session) } } }
            }.foregroundStyle(WebStyle.text).tint(WebStyle.accent)
        }
        .alert("leqra", isPresented: Binding(get: { session.error != nil }, set: { if !$0 { session.error = nil } })) {
            Button("OK") { session.error = nil }
        } message: { Text(session.error ?? "") }
        .onChange(of: scenePhase) { phase in if phase != .active && session.screen == .playing { session.setPaused(true) } }
        .statusBarHidden(session.fullscreen)
        .persistentSystemOverlays(session.fullscreen ? .hidden : .automatic)
        .task {
            while !Task.isCancelled {
                let started = ProcessInfo.processInfo.systemUptime
                if scenePhase == .active { await session.refreshPublicStatus() }
                try? await Task.sleep(nanoseconds: NetworkRefreshCadence.remainingNanoseconds(startedAt: started, now: ProcessInfo.processInfo.systemUptime))
            }
        }
    }

    private func readyRoom(landscape: Bool) -> some View {
        VStack(spacing: 0) {
            ArenaStatusBar(session: session, preview: true)
            ZStack(alignment: .topTrailing) {
                NativeGameView(scene: session.scene, highFrameRate: false, paused: true, infinity: true, landscape: landscape)
                    .blur(radius: 2).overlay(WebStyle.sunken.opacity(0.58)).allowsHitTesting(false)
                ReadyRoomView(session: session, landscape: landscape)
                if session.showScores { ArenaStandings(session: session, preview: true).padding(10) }
            }.onAppear { session.preparePreview() }
        }.background(WebStyle.sunken).clipShape(RoundedRectangle(cornerRadius: 9))
            .overlay(RoundedRectangle(cornerRadius: 9).stroke(WebStyle.edge, lineWidth: 1).allowsHitTesting(false))
    }

    private var connecting: some View {
        WebPanel(accent: true) {
            VStack(spacing: 20) {
                Text("CONNECTING.").font(.system(size: 28, weight: .black)).foregroundStyle(WebStyle.accent)
                ProgressView().tint(WebStyle.accent)
                Text(session.status).font(.system(size: 12)).foregroundStyle(WebStyle.soft)
                Button("← BACK TO THE ROOM") { session.leave() }.buttonStyle(WebButtonStyle())
            }.frame(maxWidth: .infinity)
        }.frame(maxWidth: 400).padding(20).frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func game(landscape: Bool) -> some View {
        VStack(spacing: 0) {
            ArenaStatusBar(session: session)
            if let objective = session.snapshot.objectives, ["ctf", "koth", "survival"].contains(objective.mode) { objectiveBar(objective) }
            ZStack(alignment: .topTrailing) {
                NativeGameView(scene: session.scene, highFrameRate: session.highFrameRate,
                               paused: session.paused || session.hasModal,
                               infinity: session.isInfinity, landscape: landscape, loadoutHeight: 97)
                    .accessibilityIdentifier("arenaStage")
                if !session.isInfinity && !landscape {
                    VStack { Spacer(); PilotLoadoutView(session: session).frame(height: 97); Color.clear.frame(height: 119) }.allowsHitTesting(false)
                }
                if !session.isInfinity && session.showFPS {
                    Text(session.performanceReadout()).font(WebStyle.mono()).foregroundStyle(WebStyle.accent).padding(7)
                        .background(WebStyle.sunken.opacity(0.9), in: RoundedRectangle(cornerRadius: 5)).padding(6)
                }
                if session.showScores { ArenaStandings(session: session).padding(10) }
                announcements.padding(.bottom, !session.isInfinity && !landscape ? 216 : 0)
                if session.snapshot.phase == "matchOver" || session.snapshot.result != nil {
                    results.padding(.bottom, !session.isInfinity && !landscape ? 216 : 0)
                }
            }
            if session.isInfinity || landscape { PilotLoadoutView(session: session, compact: landscape) }
        }.background(WebStyle.sunken).clipShape(RoundedRectangle(cornerRadius: session.isInfinity ? 0 : 9))
            .overlay(RoundedRectangle(cornerRadius: session.isInfinity ? 0 : 9).stroke(session.isInfinity ? .clear : WebStyle.edge, lineWidth: 1).allowsHitTesting(false))
    }

    private func objectiveBar(_ objective: ArenaObjectives) -> some View {
        HStack(spacing: 8) {
            if let survival = objective.survival {
                Text("WAVE \(survival.wave)"); Spacer(); Text("\(survival.enemiesRemaining) ENEMIES")
            } else if objective.mode == "ctf" {
                ForEach(Array(objective.flags.enumerated()), id: \.offset) { _, flag in
                    Text("TEAM \(flag.team): \(flag.home ? "FLAG HOME" : flag.carrier >= 0 ? "FLAG CARRIED" : "FLAG DROPPED")").foregroundStyle(WebStyle.paint(flag.team - 1))
                }
            } else {
                Text(objective.contested ? "HILL CONTESTED" : objective.owner == 0 ? "HILL NEUTRAL" : "HILL CONTROLLED"); Spacer()
                if objective.suddenDeath { Text("SUDDEN DEATH").foregroundStyle(WebStyle.danger) }
            }
        }.font(WebStyle.mono()).foregroundStyle(WebStyle.soft).padding(.horizontal, 12).padding(.vertical, 5).background(WebStyle.surface)
    }

    @ViewBuilder private var announcements: some View {
        if session.snapshot.phase == "countdown" {
            VStack(spacing: 8) {
                Text("\(session.selectedMode == .survival ? "WAVE" : "ROUND") \(String(format: "%02d", session.snapshot.round))").font(WebStyle.mono()).padding(8).background(WebStyle.sunken.opacity(0.9), in: RoundedRectangle(cornerRadius: 4))
                Text("\(Int(ceil(session.snapshot.phaseTime)))").font(.system(size: 96, weight: .black)).foregroundStyle(WebStyle.accent)
                Text("Bounce. Dodge. Outlast.").font(.system(size: 11)).foregroundStyle(WebStyle.soft)
            }.frame(maxWidth: .infinity, maxHeight: .infinity).allowsHitTesting(false)
        } else if session.weaponsLive {
            VStack(spacing: 8) {
                Text("WEAPONS LIVE").font(WebStyle.mono()).foregroundStyle(WebStyle.soft)
                Text("GO").font(.system(size: 96, weight: .black)).foregroundStyle(WebStyle.accent)
            }.frame(maxWidth: .infinity, maxHeight: .infinity).allowsHitTesting(false)
        } else if session.snapshot.phase == "roundOver" {
            VStack(spacing: 8) {
                Text(session.snapshot.winner < 0 ? "ROUND DRAW" : (session.snapshot.tanks.first { $0.id == session.snapshot.winner }?.name ?? "TANK") + " WINS")
                    .font(.system(size: 28, weight: .black)).foregroundStyle(WebStyle.accent)
                Text("NEW MAZE IN \(Int(ceil(session.snapshot.phaseTime)))").font(WebStyle.mono()).foregroundStyle(WebStyle.soft)
            }.padding(18).background(WebStyle.surface.opacity(0.95), in: RoundedRectangle(cornerRadius: 6))
                .frame(maxWidth: .infinity, maxHeight: .infinity).allowsHitTesting(false)
        }
    }

    private var results: some View {
        ScrollView {
            WebPanel(accent: true) {
                VStack(alignment: .leading, spacing: 14) {
                    Text("MATCH COMPLETE").font(WebStyle.mono()).foregroundStyle(WebStyle.soft)
                    Text(resultTitle).font(.system(size: 32, weight: .black)).foregroundStyle(WebStyle.accent)
                    if !resultSubtitle.isEmpty { Text(resultSubtitle).font(.system(size: 12)).foregroundStyle(WebStyle.soft) }
                    ForEach(session.standings.prefix(8)) { entry in
                        HStack { Text(entry.id == session.localID ? session.identity : entry.name).fontWeight(entry.id == session.localID ? .bold : .regular); Spacer(); Text("\(entry.score)").font(WebStyle.mono(20)) }.font(.system(size: 12)).foregroundStyle(WebStyle.paint(entry.colorIndex))
                    }
                    if session.isInfinity {
                        Button("BACK TO ROOM") { session.exitArenaToRoom() }.buttonStyle(WebButtonStyle(kind: .primary))
                    } else if session.offline || session.isHost || session.room?.matchmaking != nil {
                        Button("RUN IT BACK ↻") { session.restartMatch() }.buttonStyle(WebButtonStyle(kind: .play))
                    } else { Button("READY FOR REMATCH") { session.restartMatch() }.buttonStyle(WebButtonStyle(kind: .play)) }
                    if session.offline || session.isHost {
                        Button("Change mode or difficulty") { if session.offline { session.leave() } else { session.returnToRoom() } }.buttonStyle(WebButtonStyle())
                    } else if session.ownRoomMember?.hasParty == true {
                        Button("Return to party") { session.send(.returnParty) }.buttonStyle(WebButtonStyle())
                    } else { Button("Leave room") { session.leave() }.buttonStyle(WebButtonStyle()) }
                    if session.room != nil { Button("MATCH REPORT") { session.showSidebar = true }.buttonStyle(WebButtonStyle()) }
                }
            }.frame(maxWidth: 400).padding(16)
        }.frame(maxWidth: .infinity, maxHeight: .infinity).background(Color(hex: "#091218").opacity(0.7))
    }
    private var resultTitle: String {
        if let result = session.snapshot.result { return result.name + " WINS" }
        if let survival = session.snapshot.objectives?.survival { return survival.status == "won" ? "SURVIVAL COMPLETE" : "SQUAD DOWN." }
        if session.snapshot.winner < 0 && session.snapshot.matchStats?.players.contains(where: \.winner) != true { return "MATCH DRAW" }
        let locals = session.snapshot.matchStats?.players.filter { $0.member == session.roomMemberID || $0.controllerMember == session.roomMemberID } ?? []
        if !locals.isEmpty && !locals.contains(where: \.winner) { return "DEFEAT" }
        if session.offline && session.snapshot.isWinningSide(localID: session.localID) == false { return "DEFEAT" }
        return winningSide + " WINS"
    }
    private var resultSubtitle: String {
        if let survival = session.snapshot.objectives?.survival { return "Wave \(survival.wave), \(survival.wavesCleared) cleared" }
        return resultTitle == "DEFEAT" ? winningSide + " WINS" : ""
    }
    private var winningSide: String {
        let reportWinner = session.snapshot.matchStats?.players.first(where: \.winner)
        let tankWinner = session.snapshot.tanks.first { $0.id == session.snapshot.winner }
        let team = reportWinner?.team ?? tankWinner?.team ?? 0
        if team > 0 && session.effectiveRules.teamNames.indices.contains(team - 1) { return session.effectiveRules.teamNames[team - 1] }
        return reportWinner?.name ?? tankWinner?.name ?? "TANK"
    }
}
