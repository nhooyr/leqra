import SwiftUI
import leqraCore

struct ReadyRoomView: View {
    @ObservedObject var session: GameSession
    var landscape: Bool
    @State private var settingsOpen = false
    @State private var playersOpen = false
    @State private var codeDraft = ""
    @State private var inviteCopied = false
    @FocusState private var callsignFocused: Bool

    var body: some View {
        GeometryReader { geometry in
          ScrollView {
            WebPanel(accent: true, paddingAmount: 16) {
                Group {
                    if landscape {
                        HStack(alignment: .top, spacing: 24) {
                            intro.frame(maxWidth: .infinity)
                            configuration.frame(maxWidth: .infinity)
                        }
                    } else { VStack(alignment: .leading, spacing: 18) { intro; configuration } }
                }
            }.frame(maxWidth: landscape ? 650 : 420)
                .accessibilityElement(children: .contain).accessibilityIdentifier("readyRoomCard")
                .padding(12).frame(maxWidth: .infinity)
          }.frame(width: geometry.size.width, height: geometry.size.height)
              .accessibilityIdentifier("readyRoomScroll")
              .scrollDismissesKeyboard(.interactively)
        }.onChange(of: callsignFocused) { focused in if !focused { session.saveCallsign() } }
            .task(id: session.serverAddress) { session.scheduleCallsignAvailability() }
    }

    private var publicSelected: Bool { session.room?.infinityPublic ?? session.publicInfinitySelected }
    private var intro: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(session.room == nil ? "LOCAL ROOM" : "ONLINE ROOM").font(WebStyle.mono()).foregroundStyle(WebStyle.soft)
            (Text("READY ").foregroundColor(WebStyle.text) + Text("ROOM.").foregroundColor(WebStyle.accent))
                .font(.system(size: landscape ? 25 : 28, weight: .black)).lineSpacing(-2)
            if session.isHost {
                HStack(spacing: 9) {
                    WebSwitch(isOn: Binding(get: { publicSelected }, set: session.togglePublic)).frame(width: 51, height: 31).scaleEffect(0.7).frame(width: 35, height: 20).accessibilityIdentifier("publicInfinityToggle")
                    Text("Public Infinity").font(.system(size: 13, weight: .bold))
                    Spacer()
                }.frame(minHeight: 44)
            }
            Button { session.play() } label: {
                HStack { Spacer(); Text(playLabel); Spacer(); Image(systemName: session.isHost ? "arrow.right" : "checkmark") }
            }.buttonStyle(WebButtonStyle(kind: .play)).accessibilityIdentifier("playRoom")
                .disabled(session.room?.infinityActive == true ? session.ownRoomMember?.spectating != false : session.room != nil && session.isHost && !(session.room?.canStart ?? false) && !(publicSelected && (session.room?.canStartPublicInfinity ?? false)))
            ZStack {
                ForEach(["PUBLIC INFINITY, ENDLESS", "ENDLESS TANK ARENA, START WHEN READY", "BOT SKIRMISH, START WHEN READY"], id: \.self) { hint in
                    Text(hint).opacity(hint == readyHint ? 1 : 0).accessibilityHidden(hint != readyHint)
                }
            }.font(WebStyle.mono()).foregroundStyle(WebStyle.muted).multilineTextAlignment(.center).frame(maxWidth: .infinity)
            Button("FIND ONLINE BATTLE") { session.openQueue() }.buttonStyle(WebButtonStyle())
            if session.room == nil {
                Button("SHARE ROOM ONLINE ↗") { session.shareRoom() }.buttonStyle(WebButtonStyle(kind: .share))
            } else {
                Button {
                    UIPasteboard.general.url = session.inviteURL
                    inviteCopied = true
                    Task { @MainActor in
                        try? await Task.sleep(nanoseconds: 2_000_000_000)
                        inviteCopied = false
                    }
                } label: {
                    Text(inviteCopied ? "INVITE LINK COPIED ✓" : "COPY INVITE LINK ↗").frame(maxWidth: .infinity)
                }.buttonStyle(WebButtonStyle())
            }
            Button("Join another room ↗") { session.showJoin = true }.buttonStyle(WebButtonStyle(kind: .text)).frame(maxWidth: .infinity)
            if session.room != nil {
                Button("Leave room") { session.leave() }.buttonStyle(WebButtonStyle(kind: .danger))
                if let room = session.room { Text(room.code).font(WebStyle.mono(13, weight: .bold)).textSelection(.enabled).accessibilityIdentifier("roomCodeValue") }
            }
            Text(session.room == nil ? "Local play is ready. Share to invite online friends." : session.status.isEmpty ? "Room connected. Invite friends or deploy tanks." : session.status)
                .font(.system(size: 11)).lineSpacing(4).foregroundStyle(WebStyle.soft)
            if let room = session.room {
                Text(publicSelected ? "" : room.startError).font(.system(size: 11)).foregroundStyle(WebStyle.danger)
                    .fixedSize(horizontal: false, vertical: true).frame(maxWidth: .infinity, minHeight: 28, alignment: .topLeading)
            }
        }
    }

    private var configuration: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) { Text(session.identity).font(WebStyle.mono(11, weight: .bold)).foregroundStyle(WebStyle.paint(session.colorIndex)); Text("callsign").font(WebStyle.mono()).foregroundStyle(WebStyle.muted) }
            HStack(spacing: 8) {
                TextField("Callsign", text: $session.callsign).modifier(WebField(font: WebStyle.mono(16), color: WebStyle.paint(session.colorIndex))).focused($callsignFocused)
                    .textInputAutocapitalization(.words).autocorrectionDisabled().onSubmit { session.saveCallsign() }
                    .onChange(of: session.callsign) { value in if value.count > 16 { session.callsign = String(value.prefix(16)) } }
                    .accessibilityIdentifier("callsignField")
                AccountKeyButton(session: session, seat: 0, identity: session.identity, identifier: "openAccount")
            }
            CallsignFeedback(session: session)
            WebDisclosure(isExpanded: $settingsOpen, title: "Room settings") {
                VStack(alignment: .leading, spacing: 12) {
                    Text("ROOM NAME OR CODE").font(WebStyle.mono()).foregroundStyle(WebStyle.muted)
                    TextField("Room name", text: session.room == nil ? $session.roomName : $codeDraft)
                        .modifier(WebField()).autocorrectionDisabled()
                        .onAppear { codeDraft = session.room?.code ?? "" }
                        .onSubmit { if session.room != nil { session.send(.renameRoom(codeDraft)) } }
                        .disabled(!session.isHost)
                    Text("CHOOSE YOUR BATTLE").font(WebStyle.mono()).foregroundStyle(WebStyle.muted)
                    modeChoices
                    // Measure every mode's wrapped copy at the current width.
                    // Selecting a mode changes ink, never the settings footprint.
                    ZStack(alignment: .topLeading) {
                        ForEach(BattleMode.allCases) { mode in
                            Text(mode.help).opacity(mode == session.selectedMode ? 1 : 0)
                                .accessibilityHidden(mode != session.selectedMode)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }.font(.system(size: 10)).foregroundStyle(WebStyle.soft).frame(maxWidth: .infinity, alignment: .leading)
                    HStack(spacing: 6) {
                        Button("Rules") { session.showRules = true }
                        Button("Teams") { session.showRules = true }
                        Button("Presets") { session.showPresets = true }
                    }.buttonStyle(WebButtonStyle(compact: true))
                    ZStack(alignment: .topLeading) {
                        Text("FIRST TO 999 WAVES, UP TO 8 TANKS\nTeammates share wins. Friendly fire is off.")
                            .hidden().accessibilityHidden(true)
                        Text(ruleSummary).accessibilityIdentifier("roomRuleSummary")
                    }.font(WebStyle.mono()).foregroundStyle(WebStyle.soft).lineSpacing(4)
                        .fixedSize(horizontal: false, vertical: true).frame(maxWidth: .infinity, alignment: .leading)
                }.padding(.top, 12)
            }
            WebDisclosure(isExpanded: $playersOpen, title: "Players and bots", detail: "\(session.room?.players.count ?? session.localBots.count + 1) / \(session.room?.maxPlayers ?? 8)") {
                VStack(spacing: 10) {
                    if session.isHost {
                        Button("＋ ADD BOT") { session.addBot() }.buttonStyle(WebButtonStyle(compact: true)).accessibilityIdentifier("Add bot")
                    }
                    if let room = session.room {
                        ForEach(room.players) { member in RoomPilotRow(session: session, member: member) }
                        if !room.spectators.isEmpty {
                            Text("SPECTATORS").font(WebStyle.mono()).foregroundStyle(WebStyle.muted).frame(maxWidth: .infinity, alignment: .leading)
                            ForEach(room.spectators) { member in RoomPilotRow(session: session, member: member) }
                        }
                    } else {
                        localHuman
                        ForEach($session.localBots) { $bot in LocalBotRow(bot: $bot, teams: session.effectiveRules.teamMode == "teams") {
                            session.localBots.removeAll { $0.id == bot.id }
                        } }
                    }
                }.padding(.top, 12)
            }
            Button("CONTROLS") { session.showControls = true }.buttonStyle(WebButtonStyle(compact: true))
            if session.room != nil { Button("FIND A MATCH") { session.openQueue() }.buttonStyle(WebButtonStyle(compact: true)) }
        }
    }

    private var modeChoices: some View {
        HStack(spacing: 2) {
            ForEach(BattleMode.allCases) { mode in
                Button { session.selectMode(mode) } label: {
                    VStack(spacing: 6) {
                        Image(systemName: mode.symbol).font(.system(size: 20)).frame(height: 24)
                        Text(mode.short).font(.system(size: 10, weight: .semibold)).multilineTextAlignment(.center).frame(minHeight: 25)
                    }.frame(maxWidth: .infinity).padding(.vertical, 8)
                        .foregroundStyle(session.selectedMode == mode ? WebStyle.accent : WebStyle.muted)
                        .background(session.selectedMode == mode ? WebStyle.accentWash : .clear, in: RoundedRectangle(cornerRadius: 6))
                        .contentShape(Rectangle())
                }.buttonStyle(.plain).accessibilityLabel(mode.title).accessibilityIdentifier("mode_" + mode.rawValue).disabled(!session.isHost)
            }
        }.padding(3).background(WebStyle.sunken, in: RoundedRectangle(cornerRadius: 9))
            .overlay(RoundedRectangle(cornerRadius: 9).stroke(WebStyle.edge, lineWidth: 1).allowsHitTesting(false))
    }

    private var localHuman: some View {
        VStack(alignment: .leading, spacing: 9) {
            Text(session.identity).font(.system(size: 12, weight: .bold)).foregroundStyle(WebStyle.paint(session.colorIndex)).fixedSize(horizontal: false, vertical: true)
            PaintChoices(selected: session.colorIndex, action: session.setPaint)
            if session.effectiveRules.teamMode == "teams" {
                Picker("Team", selection: $session.localTeam) { ForEach(1...4, id: \.self) { Text("Team \($0)").tag($0) } }.font(.system(size: 12))
            }
        }.frame(maxWidth: .infinity, alignment: .leading).padding(10).background(WebStyle.sunken, in: RoundedRectangle(cornerRadius: 7))
    }
    private var playLabel: String {
        if session.room?.infinityActive == true { return "REJOIN INFINITY" }
        if session.isHost { return "PLAY" }
        let ready = session.room?.players.first(where: { $0.id == session.localID })?.ready ?? false
        return ready ? "READY ✓" : "READY"
    }
    private var readyHint: String {
        if publicSelected { return "PUBLIC INFINITY, ENDLESS" }
        return session.effectiveRules.infinity ? "ENDLESS TANK ARENA, START WHEN READY" : "BOT SKIRMISH, START WHEN READY"
    }
    private var ruleSummary: String {
        let rules = session.effectiveRules
        if rules.infinity { return rules.infinityTarget == 0 ? "ENDLESS, UP TO 8 TANKS" : "FIRST TO \(rules.infinityTarget), UP TO 8 TANKS" }
        return "FIRST TO \(rules.scoreTarget) \(rules.mode == "survival" ? "WAVES" : "WINS"), UP TO \(rules.mode == "survival" ? 4 : 8) TANKS\nTeammates share wins. Friendly fire is \(rules.friendlyFire ? "on" : "off")."
    }
}

struct PaintChoices: View {
    var selected: Int
    var action: (Int) -> Void
    var body: some View {
        HStack(spacing: 5) {
            ForEach(0..<8) { index in
                Button { action(index) } label: {
                    RoundedRectangle(cornerRadius: 4).fill(WebStyle.paint(index)).frame(width: 22, height: 22)
                        .overlay(RoundedRectangle(cornerRadius: 4).stroke(.white, lineWidth: selected == index ? 2 : 0).padding(-2).allowsHitTesting(false)).frame(maxWidth: .infinity, minHeight: 36)
                }.buttonStyle(.plain).accessibilityLabel(GamePalette.names[index])
            }
        }
    }
}

struct LocalBotRow: View {
    @Binding var bot: LocalBot
    var teams: Bool
    var remove: () -> Void
    var body: some View {
        VStack(spacing: 8) {
            HStack {
                TankMark().foregroundStyle(WebStyle.paint(bot.colorIndex))
                Text("BOT").font(WebStyle.mono()).foregroundStyle(WebStyle.muted)
                TextField("Callsign", text: $bot.name).font(.system(size: 12)).foregroundStyle(WebStyle.paint(bot.colorIndex))
                Button(action: remove) { Image(systemName: "xmark").frame(width: 32, height: 32) }.foregroundStyle(WebStyle.danger).accessibilityLabel("Remove " + bot.name)
            }
            HStack {
                Picker("Difficulty", selection: $bot.difficulty) {
                    ForEach(BotDifficulty.allCases, id: \.rawValue) { Text($0.displayName).tag($0.rawValue) }
                }.font(.system(size: 11))
                Spacer()
                if teams { Picker("Team", selection: $bot.team) { ForEach(1...4, id: \.self) { Text("Team \($0)").tag($0) } }.font(.system(size: 11)) }
            }
            PaintChoices(selected: bot.colorIndex) { bot.colorIndex = $0 }
        }.padding(10).background(WebStyle.sunken, in: RoundedRectangle(cornerRadius: 7))
    }
}

struct RoomPilotRow: View {
    @ObservedObject var session: GameSession
    let member: RoomMember
    @State private var name = ""
    private var primary: Bool { member.id == session.roomPilotID }
    private var ownedLocal: Bool { member.kind == "local" && member.owner == session.roomPilotID }
    private var owned: Bool { primary || ownedLocal }
    private var canRename: Bool { session.roomEditable && (session.isHost && member.kind == "bot" || ownedLocal) }
    private var canPaint: Bool { session.roomEditable && session.effectiveRules.teamMode == "ffa" && !member.spectating && (owned || session.isHost && member.kind == "bot") }
    private var label: String { primary ? session.identity : ownedLocal ? member.name + " (P2)" : member.name }
    private var teams: ClosedRange<Int> { session.effectiveRules.mode == "survival" && !session.effectiveRules.infinity ? 1...1 : session.effectiveRules.mode == "ctf" && !session.effectiveRules.infinity ? 1...2 : 1...4 }
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top) {
                Circle().fill(WebStyle.mapped(member.color)).frame(width: 10, height: 10).padding(.top, 3)
                Text(CallsignPolicy.displayName(label, bot: member.kind == "bot"))
                    .font(.system(size: 12, weight: owned ? .bold : .regular)).foregroundStyle(WebStyle.mapped(member.color))
                    .fixedSize(horizontal: false, vertical: true).accessibilityIdentifier(primary ? "localRoomIdentity" : "roomPilot_\(member.id)")
                Spacer(minLength: 4)
                VStack(alignment: .trailing, spacing: 2) {
                    Text(member.kind == "bot" ? "BOT" : "HUMAN PILOT")
                    if member.kind != "bot" {
                        Text((member.id == session.room?.host ? "HOST, " : "") + (member.spectating ? "WATCHING" : member.ready ? "READY" : "WAITING"))
                    }
                }.font(WebStyle.mono()).foregroundStyle(WebStyle.muted)
                if owned || session.isHost {
                    Menu {
                        if session.roomEditable && session.isHost {
                            if member.kind == "bot" {
                                ForEach(BotDifficulty.allCases, id: \.rawValue) { difficulty in
                                    Button(difficulty.displayName) { session.send(.configure(target: member.id, member: member.member, difficulty: difficulty.rawValue)) }
                                }
                            }
                            if session.effectiveRules.teamMode == "teams" && !member.spectating {
                                ForEach(teams, id: \.self) { team in Button("Team \(team)") { session.send(.configure(target: member.id, member: member.member, team: team)) } }
                            }
                        }
                        if owned { Button(member.spectating ? "Return to play" : "Spectate") { session.send(.spectate(!member.spectating, target: member.id, member: member.member)) } }
                        if session.isHost && !primary && session.room?.matchmaking == nil { Button("Remove", role: .destructive) { session.send(.kick(target: member.id, member: member.member)) } }
                    } label: { Image(systemName: "ellipsis").frame(width: 32, height: 32) }
                }
            }
            if canRename {
                HStack(spacing: 8) {
                    TextField("Callsign", text: $name).modifier(WebField()).autocorrectionDisabled()
                        .onSubmit {
                            let value = String(name.trimmingCharacters(in: .whitespacesAndNewlines).prefix(16))
                            guard !value.isEmpty else { return }
                            if ownedLocal { session.send(.renameLocal(target: member.id, member: member.member, name: value)) }
                            else { session.send(.configure(target: member.id, member: member.member, name: value)) }
                        }
                        .onAppear { name = member.name }.onChange(of: member.name) { name = $0 }
                        .onChange(of: name) { value in if ownedLocal { session.scheduleCallsignAvailability(localName: value) } }
                        .accessibilityIdentifier(ownedLocal ? "localCallsignField" : "botCallsign_\(member.id)")
                    if ownedLocal { AccountKeyButton(session: session, seat: 1, identity: label, identifier: "openLocalAccount") }
                }
                if ownedLocal {
                    CallsignFeedback(session: session, seat: 1)
                }
            }
            if canPaint {
                PaintChoices(selected: member.colorIndex ?? GamePalette.colors.firstIndex(of: member.color) ?? 0) { session.send(.paint(target: member.id, member: member.member, colorIndex: $0)) }
            }
        }.padding(10).background(WebStyle.sunken, in: RoundedRectangle(cornerRadius: 7))
    }
}

struct AccountKeyButton: View {
    @ObservedObject var session: GameSession
    let seat: Int
    let identity: String
    let identifier: String

    var body: some View {
        Button("Account") { session.openAccount(seat: seat) }
            .buttonStyle(WebButtonStyle(compact: true)).frame(width: 76)
            .accessibilityLabel("Account key for " + identity).accessibilityIdentifier(identifier)
    }
}

/// A fixed three-line slot keeps checking and conflict feedback from moving the
/// callsign editor or the controls below it.
struct CallsignFeedback: View {
    @ObservedObject var session: GameSession
    var seat = 0
    private var message: String { seat == 1 ? session.localCallsignFeedback : session.callsignFeedback }
    private var reserved: Bool { seat == 1 ? session.localCallsignReserved : session.callsignReserved }
    private var taken: Bool { message == "Used online; offline is OK." }
    private var identifier: String { seat == 1 ? "localCallsignAvailability" : "callsignAvailability" }
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(message.isEmpty && session.callsignChecking ? "Checking online callsign…" : message)
                .foregroundStyle(session.callsignChecking && message.isEmpty ? WebStyle.muted : WebStyle.danger)
                .frame(height: 20, alignment: .leading).accessibilityIdentifier(identifier)
            Button("Yours? Import account key") { session.openAccount(seat: seat) }
                .opacity(taken && !reserved ? 1 : 0).disabled(!taken || reserved)
                .accessibilityHidden(!taken || reserved).frame(height: 20, alignment: .leading)
            Button("Generate random?") { session.generateRandomCallsign(seat: seat) }
                .opacity(taken || reserved ? 1 : 0).disabled(!(taken || reserved) || session.callsignGenerating)
                .accessibilityHidden(!(taken || reserved)).frame(height: 20, alignment: .leading)
                .accessibilityIdentifier(seat == 1 ? "generateLocalCallsign" : "generateCallsign")
        }.font(.system(size: 10)).buttonStyle(.plain).foregroundStyle(WebStyle.accent)
            .frame(maxWidth: .infinity, alignment: .leading).frame(height: 60, alignment: .topLeading)
    }
}
