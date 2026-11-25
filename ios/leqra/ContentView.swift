import SwiftUI
import leqraCore

struct ContentView: View {
    @ObservedObject var session: GameSession
    @Environment(\.scenePhase) private var scenePhase
    private var statusAtBottom: Bool {
        NativePlatform.isDesktop
    }
    private var statusInHeader: Bool {
        !NativePlatform.isDesktop && UIDevice.current.userInterfaceIdiom == .pad
    }
    private var nativeLayoutProbeWidth: CGFloat? {
        #if DEBUG
            let arguments = ProcessInfo.processInfo.arguments
            guard arguments.contains("--probe-native-layout"),
                let index = arguments.firstIndex(of: "--probe-content-width"),
                arguments.indices.contains(index + 1), let width = Double(arguments[index + 1]), width > 0
            else { return nil }
            return CGFloat(width)
        #else
            return nil
        #endif
    }
    var body: some View {
        GeometryReader { geometry in
            let landscape = geometry.size.width > geometry.size.height
            let immersive = !statusAtBottom && session.screen == .playing
            let bottomInset = immersive ? geometry.safeAreaInsets.bottom : 0
            ZStack {
                WebStyle.page.ignoresSafeArea()
                Group {
                    VStack(spacing: 0) {
                        GameHeader(
                            session: session, landscape: landscape, availableWidth: geometry.size.width,
                            embeddedStatus: statusInHeader, statusPreview: session.readyRoom)
                        if session.readyRoom {
                            readyRoom(landscape: landscape, bottomInset: bottomInset)
                        } else if session.screen == .connecting {
                            connecting
                        } else {
                            game(landscape: landscape, bottomInset: bottomInset, width: geometry.size.width)
                        }
                    }.padding(.horizontal, session.screen == .playing && session.isInfinity ? 0 : 9)
                        .padding(.top, landscape ? 5 : 9).padding(
                            .bottom,
                            immersive || session.screen == .playing && session.isInfinity ? 0 : 8
                        )
                        .ignoresSafeArea(.container, edges: immersive ? .bottom : [])
                        .allowsHitTesting(
                            !session.paused && !session.showRules && !session.showControls
                                && !session.showAccount && !session.showJoin && !session.showPresets
                                && !session.showQueues && !session.showSidebar)
                    if session.paused && session.screen == .playing {
                        PauseCard(session: session, landscape: landscape)
                    }
                    if session.showSidebar { SidebarPanel(session: session) }
                    if session.showPresets { PresetsPanel(session: session) }
                    if session.showQueues { QueuePanel(session: session) }
                    if session.showJoin { JoinRoomPanel(session: session) }
                    if session.showRules { RulesEditor(session: session) }
                    if session.showControls { ControlsPanel(session: session) }
                    if session.showAccount { AccountPanel(session: session) }
                }.accessibilityHidden(session.showShowcase).allowsHitTesting(!session.showShowcase)
                if session.showShowcase {
                    showcase(landscape: landscape, width: geometry.size.width)
                }
            }.foregroundStyle(WebStyle.text).tint(WebStyle.accent)
        }
        .frame(maxWidth: nativeLayoutProbeWidth)
        .alert(
            "leqra",
            isPresented: Binding(get: { session.error != nil }, set: { if !$0 { session.error = nil } })
        ) {
            Button("OK") { session.error = nil }
        } message: {
            Text(session.error ?? "")
        }
        .onAppear { session.syncGamepads() }
        .onChange(of: session.gamepadTargets) { _ in session.syncGamepads() }
        .onChange(of: scenePhase) { phase in session.scenePhaseChanged(phase) }
        .statusBarHidden(session.fullscreen)
        .persistentSystemOverlays(session.fullscreen ? .hidden : .automatic)
        .task(id: scenePhase) {
            guard scenePhase == .active else { return }
            while !Task.isCancelled {
                let started = ProcessInfo.processInfo.systemUptime
                await session.refreshPublicStatus()
                try? await Task.sleep(
                    nanoseconds: NetworkRefreshCadence.remainingNanoseconds(
                        startedAt: started, now: ProcessInfo.processInfo.systemUptime))
            }
        }
    }

    private func showcase(landscape: Bool, width: CGFloat) -> some View {
        VStack(spacing: 0) {
            GameHeader(
                session: session, landscape: landscape, availableWidth: width, showcase: true,
                embeddedStatus: statusInHeader
            )
            .allowsHitTesting(false)
            if let frame = session.showcaseFrame {
                VStack(spacing: 0) {
                    if !statusAtBottom && !statusInHeader {
                        ArenaStatusBar(session: session, showcase: frame).allowsHitTesting(false)
                    }
                    NativeGameView(
                        scene: session.showcaseScene, highFrameRate: session.highFrameRate,
                        paused: false, infinity: true, landscape: landscape,
                        showsTouchControls: !NativePlatform.isDesktop
                    )
                    .accessibilityIdentifier("showcaseStage")
                    PilotLoadoutView(
                        session: session, compact: landscape || statusInHeader, showcase: frame,
                        inline: statusInHeader && width >= 600, availableWidth: width
                    )
                    .allowsHitTesting(false)
                    if statusAtBottom {
                        ArenaStatusBar(session: session, showcase: frame, atBottom: true)
                            .allowsHitTesting(false)
                    }
                }.background(WebStyle.sunken)
            }
        }.padding(.top, landscape ? 5 : 9)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(WebStyle.page.ignoresSafeArea())
            .onAppear { session.configureShowcase(portrait: !landscape) }
            .onChange(of: landscape) { session.configureShowcase(portrait: !$0) }
    }

    private func readyRoom(landscape: Bool, bottomInset: CGFloat) -> some View {
        VStack(spacing: 0) {
            if !statusAtBottom && !statusInHeader { ArenaStatusBar(session: session, preview: true) }
            ZStack(alignment: .topTrailing) {
                NativeGameView(
                    scene: session.scene, highFrameRate: false, paused: true, infinity: true,
                    landscape: landscape,
                    renderingSuspended: session.showQuickTour, controlBottomInset: bottomInset
                )
                .accessibilityIdentifier("readyRoomStage")
                .blur(radius: 2).overlay(WebStyle.sunken.opacity(0.58)).allowsHitTesting(false)
                ReadyRoomView(session: session, landscape: landscape)
                    .padding(.bottom, bottomInset)
                if session.showScores { ArenaStandings(session: session, preview: true).padding(10) }
            }.onAppear { session.preparePreview() }
            if statusAtBottom { ArenaStatusBar(session: session, preview: true, atBottom: true) }
        }.background(WebStyle.sunken).clipShape(RoundedRectangle(cornerRadius: 9))
            .overlay(
                RoundedRectangle(cornerRadius: 9).stroke(WebStyle.edge, lineWidth: 1).allowsHitTesting(false))
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

    private func game(landscape: Bool, bottomInset: CGFloat, width: CGFloat) -> some View {
        let split = session.isInfinity && session.secondaryLocalID != nil
        let canControl = !session.spectating || session.secondaryLocalID != nil
        let desktopPair = NativePlatform.isDesktop && !session.spectating && session.secondaryLocalID != nil
        let overlayHeight: CGFloat =
            !NativePlatform.isDesktop && !session.isInfinity && !landscape && !session.spectating ? 119 : 0
        return VStack(spacing: 0) {
            if !statusAtBottom && !statusInHeader { ArenaStatusBar(session: session) }
            if let objective = session.snapshot.objectives,
                ["ctf", "koth", "survival"].contains(objective.mode)
            {
                objectiveBar(objective)
            }
            if canControl {
                LocalPilotLoadouts(
                    session: session, landscape: landscape, tablet: statusInHeader, availableWidth: width
                )
                .overlay(alignment: .bottom) {
                    WebStyle.border.frame(height: 1).allowsHitTesting(false)
                }
            }
            ZStack(alignment: .topTrailing) {
                if split {
                    if landscape {
                        HStack(spacing: 1) {
                            splitArena(seat: 0, landscape: landscape, bottomInset: bottomInset)
                            splitArena(seat: 1, landscape: landscape, bottomInset: bottomInset)
                        }
                    } else {
                        VStack(spacing: 1) {
                            splitArena(seat: 0, landscape: landscape, bottomInset: 0)
                            splitArena(seat: 1, landscape: landscape, bottomInset: bottomInset)
                        }
                    }
                } else {
                    NativeGameView(
                        scene: session.scene, highFrameRate: session.highFrameRate,
                        paused: session.paused || session.hasModal,
                        infinity: session.isInfinity, landscape: landscape,
                        spectating: !canControl,
                        hardwareInputScene: desktopPair || session.secondaryLocalID == nil
                            ? session.scene : session.secondaryScene,
                        secondaryHardwareInputScene: desktopPair ? session.secondaryScene : nil,
                        showsTouchControls: !NativePlatform.isDesktop && !session.spectating,
                        mouseTargetScene: NativePlatform.isDesktop && !session.spectating
                            ? session.scene : nil,
                        renderingSuspended: session.showQuickTour, controlBottomInset: bottomInset
                    )
                    .accessibilityIdentifier("arenaStage")
                }
                if session.showScores { ArenaStandings(session: session).padding(10) }
                announcements.padding(.bottom, overlayHeight)
                if !session.godlikeNotice.isEmpty {
                    VStack {
                        Text(session.godlikeNotice).font(.system(size: 12, weight: .bold)).foregroundStyle(
                            Color(hex: "#ffc46b")
                        )
                        .fixedSize(horizontal: false, vertical: true).padding(10)
                        .background(WebStyle.sunken.opacity(0.94), in: RoundedRectangle(cornerRadius: 6))
                        .accessibilityIdentifier("godlikeSpawnNotice")
                        Spacer()
                    }.frame(maxWidth: .infinity).padding(.horizontal, 12).padding(.top, 30).allowsHitTesting(
                        false)
                }
                if canControl && !session.presentingFinalShot
                    && (session.snapshot.phase == "matchOver" || session.snapshot.result != nil)
                {
                    results.padding(.bottom, overlayHeight)
                }
            }
            if statusAtBottom { ArenaStatusBar(session: session, atBottom: true) }
        }.background(WebStyle.sunken).clipShape(RoundedRectangle(cornerRadius: 9))
            .overlay(
                RoundedRectangle(cornerRadius: 9).stroke(
                    session.isInfinity ? .clear : WebStyle.edge, lineWidth: 1
                ).allowsHitTesting(false))
    }

    private func splitArena(seat: Int, landscape: Bool, bottomInset: CGFloat) -> some View {
        let desktopPair = NativePlatform.isDesktop && !session.spectating
        return VStack(spacing: 0) {
            NativeGameView(
                scene: seat == 0 ? session.scene : session.secondaryScene,
                highFrameRate: session.highFrameRate, paused: session.paused || session.hasModal,
                infinity: true, landscape: landscape,
                hardwareInputScene: desktopPair ? session.scene : session.secondaryScene,
                secondaryHardwareInputScene: desktopPair ? session.secondaryScene : nil,
                acceptsHardware: seat == 0, showsTouchControls: !NativePlatform.isDesktop && seat == 0,
                mouseTargetScene: NativePlatform.isDesktop && seat == 0
                    ? session.scene : session.secondaryScene,
                renderingSuspended: session.showQuickTour, controlBottomInset: bottomInset
            )
            .accessibilityIdentifier(seat == 0 ? "arenaStage" : "secondaryArenaStage")
        }.frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func objectiveBar(_ objective: ArenaObjectives) -> some View {
        HStack(spacing: 8) {
            if let survival = objective.survival {
                Text("WAVE \(survival.wave)")
                Spacer()
                Text("\(survival.enemiesRemaining) ENEMIES")
            } else if objective.mode == "ctf" {
                ForEach(Array(objective.flags.enumerated()), id: \.offset) { _, flag in
                    let colors = session.effectiveRules.teamColors
                    let paint = colors.indices.contains(flag.team - 1) ? colors[flag.team - 1] : flag.team - 1
                    Text(
                        "TEAM \(flag.team): \(flag.home ? "FLAG HOME" : flag.carrier >= 0 ? "FLAG CARRIED" : "FLAG DROPPED")"
                    ).foregroundStyle(WebStyle.paint(paint))
                }
            } else {
                Text(
                    objective.contested
                        ? "HILL CONTESTED" : objective.owner == 0 ? "HILL NEUTRAL" : "HILL CONTROLLED")
                Spacer()
                if objective.suddenDeath { Text("SUDDEN DEATH").foregroundStyle(WebStyle.danger) }
            }
        }.font(WebStyle.mono()).foregroundStyle(WebStyle.soft).padding(.horizontal, 12).padding(.vertical, 5)
            .background(WebStyle.surface)
    }

    @ViewBuilder private var announcements: some View {
        if session.snapshot.phase == "countdown" {
            VStack(spacing: 8) {
                Text(
                    "\(session.selectedMode == .survival ? "WAVE" : "ROUND") \(String(format: "%02d", session.snapshot.round))"
                ).font(WebStyle.mono()).padding(8).background(
                    WebStyle.sunken.opacity(0.9), in: RoundedRectangle(cornerRadius: 4))
                Text("\(Int(ceil(session.snapshot.phaseTime)))").font(.system(size: 96, weight: .black))
                    .foregroundStyle(WebStyle.accent)
                Text("Bounce. Dodge. Outlast.").font(.system(size: 11)).foregroundStyle(WebStyle.soft)
            }.frame(maxWidth: .infinity, maxHeight: .infinity).allowsHitTesting(false)
        } else if session.weaponsLive {
            VStack(spacing: 8) {
                Text("WEAPONS LIVE").font(WebStyle.mono()).foregroundStyle(WebStyle.soft)
                Text("GO").font(.system(size: 96, weight: .black)).foregroundStyle(WebStyle.accent)
            }.frame(maxWidth: .infinity, maxHeight: .infinity).allowsHitTesting(false)
        } else if session.snapshot.phase == "roundOver", !session.presentingFinalShot {
            VStack(spacing: 8) {
                Text(
                    session.snapshot.winner < 0
                        ? "ROUND DRAW" : (session.winnerIdentity?.label ?? "TANK") + " WINS"
                )
                .font(.system(size: 28, weight: .black)).foregroundStyle(winnerColor)
                Text("NEW MAZE IN \(Int(ceil(session.snapshot.phaseTime)))").font(WebStyle.mono())
                    .foregroundStyle(WebStyle.soft)
            }.padding(18).background(WebStyle.surface, in: RoundedRectangle(cornerRadius: 6))
                .overlay(
                    RoundedRectangle(cornerRadius: 6).stroke(WebStyle.edge, lineWidth: 1)
                        .allowsHitTesting(false)
                )
                .accessibilityIdentifier("roundResultCard")
                .frame(maxWidth: .infinity, maxHeight: .infinity).allowsHitTesting(false)
        }
    }

    private var results: some View {
        ScrollView {
            WebPanel(accent: true) {
                VStack(alignment: .leading, spacing: 14) {
                    Text("MATCH COMPLETE").font(WebStyle.mono()).foregroundStyle(WebStyle.soft)
                    Text(resultTitle).font(.system(size: 32, weight: .black)).foregroundStyle(
                        resultTitle == "DEFEAT" ? WebStyle.danger : winnerColor)
                    if !resultSubtitle.isEmpty {
                        Text(resultSubtitle).font(.system(size: 12)).foregroundStyle(winnerColor)
                    }
                    ForEach(session.standings.prefix(8)) { entry in
                        let seat = session.localPilotSeat(entry.id)
                        HStack {
                            Text(
                                CallsignPolicy.displayName(entry.name, bot: entry.bot)
                                    + (seat.map { " (P\($0))" } ?? "")
                            ).fontWeight(seat != nil ? .bold : .regular)
                            Spacer()
                            Text("\(entry.score)").font(WebStyle.mono(20))
                        }.font(.system(size: 12)).foregroundStyle(WebStyle.paint(entry.colorIndex))
                    }
                    if session.isInfinity {
                        Button("BACK TO ROOM") { session.exitArenaToRoom() }.buttonStyle(
                            WebButtonStyle(kind: .primary))
                    } else if session.offline || session.isHost || session.room?.matchmaking != nil {
                        Button("RUN IT BACK ↻") { session.restartMatch() }.buttonStyle(
                            WebButtonStyle(kind: .play))
                    } else {
                        Button("READY FOR REMATCH") { session.restartMatch() }.buttonStyle(
                            WebButtonStyle(kind: .play))
                    }
                    if session.offline || session.isHost {
                        Button("Change mode or difficulty") {
                            if session.offline { session.leave() } else { session.returnToRoom() }
                        }.buttonStyle(WebButtonStyle())
                    } else if session.ownRoomMember?.hasParty == true {
                        Button("Return to party") { session.send(.returnParty) }.buttonStyle(WebButtonStyle())
                    } else {
                        Button("Leave room") { session.leave() }.buttonStyle(WebButtonStyle())
                    }
                    if session.room != nil {
                        Button("MATCH REPORT") { session.showSidebar = true }.buttonStyle(WebButtonStyle())
                    }
                }
            }.frame(maxWidth: 400).padding(16)
        }.frame(maxWidth: .infinity, maxHeight: .infinity).background(Color(hex: "#091218").opacity(0.7))
    }
    private var resultTitle: String {
        if session.snapshot.result != nil { return (session.winnerIdentity?.label ?? "TANK") + " WINS" }
        if let survival = session.snapshot.objectives?.survival {
            return survival.status == "won" ? "SURVIVAL COMPLETE" : "SQUAD DOWN."
        }
        if session.snapshot.winner < 0
            && session.snapshot.matchStats?.players.contains(where: \.winner) != true
        {
            return "MATCH DRAW"
        }
        let locals =
            session.snapshot.matchStats?.players.filter {
                $0.member == session.roomMemberID || $0.controllerMember == session.roomMemberID
            } ?? []
        if !locals.isEmpty && !locals.contains(where: \.winner) { return "DEFEAT" }
        if session.offline && session.snapshot.isWinningSide(localID: session.localID) == false {
            return "DEFEAT"
        }
        return winningSide + " WINS"
    }
    private var resultSubtitle: String {
        if let survival = session.snapshot.objectives?.survival {
            return "Wave \(survival.wave), \(survival.wavesCleared) cleared"
        }
        return resultTitle == "DEFEAT" ? winningSide + " WINS" : ""
    }
    private var winningSide: String {
        session.winnerIdentity?.label ?? "TANK"
    }
    private var winnerColor: Color {
        session.winnerIdentity.map { WebStyle.mapped($0.color) } ?? WebStyle.accent
    }
}
