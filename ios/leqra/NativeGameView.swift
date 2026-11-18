import SwiftUI
import SpriteKit
import GameController
import leqraCore

@MainActor
final class NativeInputSettings: ObservableObject {
    static let shared = NativeInputSettings()
    static let changed = Notification.Name("leqra.nativeInputSettingsChanged")
    @Published private(set) var bindings: NativeControlBindings
    @Published var mouseAim: Bool { didSet { if oldValue != mouseAim { save() } } }
    @Published var mouseFire: Bool { didSet { if oldValue != mouseFire { save() } } }
    private let defaults: UserDefaults

    init(defaults: UserDefaults = NativePreferences.current) {
        self.defaults = defaults
        let stored = NativeControlPreferences.load(from: defaults)
        bindings = stored.bindings; mouseAim = stored.mouseAim; mouseFire = stored.mouseFire
    }
    func assign(keyCode: Int, layout: Int, action: NativeControlAction) throws {
        let next = try bindings.assigning(keyCode, layout: layout, action: action)
        guard next != bindings else { return }
        bindings = next; save()
    }
    func resetBindings() { bindings = .defaults; save() }
    func resetAll() {
        bindings = .defaults; mouseAim = true; mouseFire = true; save()
    }
    private func save() {
        var stored = NativeControlPreferences()
        stored.bindings = bindings; stored.mouseAim = mouseAim; stored.mouseFire = mouseFire
        stored.save(to: defaults)
        NotificationCenter.default.post(name: Self.changed, object: self)
    }
}

@MainActor
final class NativeHardwarePresence: ObservableObject {
    static let shared = NativeHardwarePresence()
    static let changed = Notification.Name("leqra.nativeHardwarePresenceChanged")
    static let escapePressed = Notification.Name("leqra.nativeHardwareEscapePressed")
    @Published private(set) var keyboardConnected = false
    @Published private(set) var mouseConnected = false
    private var observers: [NSObjectProtocol] = []
    private weak var escapeButton: GCControllerButtonInput?
    private var previousEscapeHandler: GCControllerButtonValueChangedHandler?
    private init() {
        refresh()
        for name in [Notification.Name.GCKeyboardDidConnect, .GCKeyboardDidDisconnect, .GCMouseDidConnect, .GCMouseDidDisconnect] {
            observers.append(NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.refresh() }
            })
        }
    }
    func refresh() {
        let keyboard = GCKeyboard.coalesced
        keyboardConnected = keyboard != nil
        mouseConnected = !GCMouse.mice().isEmpty
        let nextEscape = keyboard?.keyboardInput?.button(forKeyCode: .escape)
        if nextEscape !== escapeButton {
            escapeButton?.pressedChangedHandler = previousEscapeHandler
            escapeButton = nextEscape
            previousEscapeHandler = nextEscape?.pressedChangedHandler
            let previous = previousEscapeHandler
            nextEscape?.pressedChangedHandler = { button, value, pressed in
                previous?(button, value, pressed)
                guard pressed else { return }
                Task { @MainActor in
                    NotificationCenter.default.post(name: NativeHardwarePresence.escapePressed, object: nil)
                }
            }
        }
        NotificationCenter.default.post(name: Self.changed, object: self)
    }
    // Simulator-injected physical key/pointer events do not always create a
    // GameController device. Receiving the hardware event is also evidence.
    func noteKeyboard() { keyboardConnected = true }
    func noteMouse() { mouseConnected = true }
}

struct NativeKeyCaptureView: UIViewRepresentable {
    var onKey: (Int) -> Void
    var onCancel: () -> Void
    var onError: (String) -> Void = { _ in }
    func makeUIView(context: Context) -> KeyCaptureResponder {
        let view = KeyCaptureResponder(); updateUIView(view, context: context); return view
    }
    func updateUIView(_ view: KeyCaptureResponder, context: Context) {
        view.onKey = onKey; view.onCancel = onCancel; view.onError = onError
        if view.window != nil { view.becomeFirstResponder() }
    }
    final class KeyCaptureResponder: UIView {
        var onKey: (Int) -> Void = { _ in }
        var onCancel: () -> Void = {}
        var onError: (String) -> Void = { _ in }
        private var escapeObserver: NSObjectProtocol?
        override init(frame: CGRect) {
            super.init(frame: frame)
            observeHardwareEscape()
        }
        required init?(coder: NSCoder) {
            super.init(coder: coder)
            observeHardwareEscape()
        }
        deinit { if let escapeObserver { NotificationCenter.default.removeObserver(escapeObserver) } }
        private func observeHardwareEscape() {
            _ = NativeHardwarePresence.shared
            escapeObserver = NotificationCenter.default.addObserver(forName: NativeHardwarePresence.escapePressed, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in
                    guard let self, self.window != nil else { return }
                    self.onCancel()
                }
            }
        }
        override var canBecomeFirstResponder: Bool { true }
        override var keyCommands: [UIKeyCommand]? {
            let escape = UIKeyCommand(input: UIKeyCommand.inputEscape, modifierFlags: [], action: #selector(cancelCapture))
            escape.wantsPriorityOverSystemBehavior = true
            return [escape]
        }
        @objc private func cancelCapture() { onCancel() }

        override func didMoveToWindow() {
            super.didMoveToWindow()
            guard window != nil else { return }
            becomeFirstResponder()
            #if DEBUG
            // Exercise the physical-keyboard notification route in UI tests
            // without claiming the simulator synthesized a hardware Escape.
            if ProcessInfo.processInfo.arguments.contains("--probe-hardware-escape") {
                DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
                    guard let self, self.window != nil else { return }
                    NotificationCenter.default.post(name: NativeHardwarePresence.escapePressed, object: nil)
                }
            }
            #endif
        }
        override func pressesBegan(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
            for press in presses {
                guard let key = press.key else { continue }
                NativeHardwarePresence.shared.noteKeyboard()
                if key.keyCode == .keyboardEscape { onCancel(); return }
                guard key.modifierFlags.intersection([.command, .control, .alternate]).isEmpty else {
                    onError("System shortcuts cannot be assigned."); return
                }
                onKey(key.keyCode.rawValue); return
            }
        }
    }
}

/// Controller assignments belong to the session, so changing arena layouts
/// or opening a menu cannot swap the two local controllers.
@MainActor
final class NativeGamepads {
    var onMenu: () -> Void = {}
    var gameplayInputAllowed: () -> Bool = { false }
    private var controllers: [GCController?] = [nil, nil]
    private var observers: [NSObjectProtocol] = []
    private weak var primary: GameScene?
    private weak var secondary: GameScene?
    private weak var practice: GameScene?
    private var supportEnabled = true
    private var enabled = false
    private var routes: [ObjectIdentifier: GameScene] = [:]
    private var waitingForNeutral: Set<ObjectIdentifier> = []

    init() {
        for name in [Notification.Name.GCControllerDidConnect, .GCControllerDidDisconnect] {
            observers.append(NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.syncControllers() }
            })
        }
        syncControllers()
    }

    deinit { observers.forEach(NotificationCenter.default.removeObserver) }

    func setSupportEnabled(_ value: Bool) {
        guard supportEnabled != value else { return }
        supportEnabled = value
        updateRoutes()
    }

    func configure(primary: GameScene?, secondary: GameScene?, enabled: Bool) {
        self.primary = primary; self.secondary = secondary; self.enabled = enabled
        updateRoutes()
    }

    func setPractice(_ scene: GameScene?) {
        practice = scene
        updateRoutes()
    }

    func rearmPractice() {
        guard supportEnabled, let practice, let controller = controllers.compactMap({ $0 }).first,
              let pad = controller.extendedGamepad else { return }
        practice.setGamepadInput(GameInput())
        let id = ObjectIdentifier(controller)
        waitingForNeutral.remove(id)
        if Self.input(pad) != GameInput() { waitingForNeutral.insert(id) }
    }

    private func syncControllers() {
        let available = GCController.controllers().filter { $0.extendedGamepad != nil }
        for index in controllers.indices {
            guard let controller = controllers[index], !available.contains(where: { $0 === controller }) else { continue }
            controller.extendedGamepad?.valueChangedHandler = nil
            controller.extendedGamepad?.buttonMenu.pressedChangedHandler = nil
            controllers[index] = nil
        }
        for controller in available where !controllers.contains(where: { $0 === controller }) {
            guard let index = controllers.firstIndex(where: { $0 == nil }), let pad = controller.extendedGamepad else { break }
            controllers[index] = controller
            controller.playerIndex = index == 0 ? .index1 : .index2
            controller.handlerQueue = .main
            let id = ObjectIdentifier(controller)
            pad.valueChangedHandler = { [weak self] pad, _ in
                // Deliver each edge on the configured queue. Deferring a read
                // of the profile could coalesce a quick press and release.
                MainActor.assumeIsolated { self?.apply(Self.input(pad), from: id) }
            }
            pad.buttonMenu.pressedChangedHandler = { [weak self] _, _, pressed in
                guard pressed else { return }
                MainActor.assumeIsolated { self?.menuPressed(by: index, id: id) }
            }
        }
        updateRoutes()
    }

    private func target(for index: Int) -> GameScene? {
        guard let seat = NativeGamepadControls.seat(for: index, connected: controllers.compactMap { $0 }.count,
                                                    primary: primary != nil, secondary: secondary != nil) else { return nil }
        return seat == 0 ? primary : secondary
    }

    private func updateRoutes() {
        var next: [ObjectIdentifier: GameScene] = [:]
        for (index, controller) in controllers.enumerated() where supportEnabled {
            guard let controller, let pad = controller.extendedGamepad else { continue }
            let id = ObjectIdentifier(controller)
            let scene: GameScene?
            if let practice {
                guard next.isEmpty else { break }
                scene = practice
            } else {
                scene = enabled ? target(for: index) : nil
            }
            guard let scene else { continue }
            next[id] = scene
            if routes[id] !== scene {
                waitingForNeutral.remove(id)
                if Self.input(pad) != GameInput() { waitingForNeutral.insert(id) }
            }
        }
        for (id, scene) in routes where next[id] !== scene { scene.setGamepadInput(GameInput()) }
        waitingForNeutral.formIntersection(next.keys)
        routes = next
    }

    private func apply(_ input: GameInput, from id: ObjectIdentifier) {
        guard let scene = routes[id], scene === practice || gameplayInputAllowed() else { return }
        if waitingForNeutral.contains(id) {
            guard input == GameInput() else { return }
            waitingForNeutral.remove(id)
        }
        scene.setGamepadInput(input)
    }

    private func menuPressed(by index: Int, id: ObjectIdentifier) {
        guard supportEnabled, let controller = controllers[index], ObjectIdentifier(controller) == id,
              practice == nil, target(for: index) != nil else { return }
        onMenu()
    }

    private static func input(_ pad: GCExtendedGamepad) -> GameInput {
        NativeGamepadControls.input(leftX: Double(pad.leftThumbstick.xAxis.value), leftY: -Double(pad.leftThumbstick.yAxis.value),
                                   rightX: Double(pad.rightThumbstick.xAxis.value), rightY: -Double(pad.rightThumbstick.yAxis.value),
                                   forward: pad.dpad.up.isPressed, reverse: pad.dpad.down.isPressed,
                                   left: pad.dpad.left.isPressed, right: pad.dpad.right.isPressed,
                                   fire: pad.buttonA.isPressed || pad.rightTrigger.isPressed || pad.rightShoulder.isPressed)
    }
}

struct NativeGameView: UIViewRepresentable {
    let scene: GameScene
    let highFrameRate: Bool
    let paused: Bool
    var infinity: Bool = true
    var landscape: Bool = false
    var loadoutHeight: CGFloat = 97
    var spectating = false
    var hardwareInputScene: GameScene? = nil
    var acceptsHardware = true
    var showsTouchControls = true
    var mouseTargetScene: GameScene? = nil
    var renderingSuspended = false

    func makeUIView(context: Context) -> UIView {
        let container = KeyboardGameContainer(scene: scene)
        configure(container)
        return container
    }

    func updateUIView(_ view: UIView, context: Context) {
        if let container = view as? KeyboardGameContainer { configure(container) }
    }

    private func configure(_ container: KeyboardGameContainer) {
        scene.configureLayout(infinity: infinity, landscape: landscape, loadoutHeight: loadoutHeight,
                              spectating: spectating, showsTouchControls: showsTouchControls)
        container.configure(scene: scene, highFrameRate: highFrameRate, paused: paused, spectating: spectating,
                            hardwareScene: hardwareInputScene ?? scene, acceptsHardware: acceptsHardware,
                            mouseScene: mouseTargetScene ?? hardwareInputScene ?? scene, renderingSuspended: renderingSuspended)
    }
}

/// Only the primary view owns the keyboard. Both views can receive
/// pointer events, while SpriteKit touch gestures stay on the primary scene.
private final class KeyboardGameContainer: UIView {
    private let gameView = SKView()
    private var pressedKeys = Set<UIKeyboardHIDUsage>()
    private var highFrameRate = true
    private var paused = false
    private var spectating = false
    private var acceptsHardware = true
    private weak var hardwareScene: GameScene?
    private weak var mouseScene: GameScene?
    private var gameScene: GameScene? { gameView.scene as? GameScene }
    private var inputObservers: [NSObjectProtocol] = []

    init(scene: GameScene) {
        super.init(frame: .zero)
        isMultipleTouchEnabled = true
        isAccessibilityElement = true
        accessibilityIdentifier = "arenaStage"
        accessibilityLabel = "Tank arena"
        gameView.frame = bounds
        gameView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        gameView.isMultipleTouchEnabled = true
        gameView.isAccessibilityElement = false
        gameView.ignoresSiblingOrder = true
        gameView.shouldCullNonVisibleNodes = true
        addSubview(gameView)
        gameView.presentScene(scene)
        _ = NativeHardwarePresence.shared
        for name in [NativeInputSettings.changed, NativeHardwarePresence.changed] {
            inputObservers.append(NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.resetHardwareControls() }
            })
        }
        inputObservers.append(NotificationCenter.default.addObserver(forName: NativeHardwarePresence.escapePressed, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.window != nil, self.acceptsHardware, self.gameScene?.onEscape != nil else { return }
                self.closeShowcase()
            }
        })
        let hover = UIHoverGestureRecognizer(target: self, action: #selector(pointerHover(_:)))
        hover.allowedTouchTypes = [NSNumber(value: UITouch.TouchType.indirectPointer.rawValue)]
        addGestureRecognizer(hover)
        let press = PrimaryMousePressRecognizer(target: self, action: #selector(pointerPress(_:)))
        press.minimumPressDuration = 0
        press.allowedTouchTypes = [NSNumber(value: UITouch.TouchType.indirectPointer.rawValue)]
        press.cancelsTouchesInView = true
        addGestureRecognizer(press)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    deinit { for observer in inputObservers { NotificationCenter.default.removeObserver(observer) } }

    func configure(scene: GameScene, highFrameRate: Bool, paused: Bool, spectating: Bool,
                   hardwareScene: GameScene, acceptsHardware: Bool, mouseScene: GameScene, renderingSuspended: Bool) {
        if self.hardwareScene !== hardwareScene { resetKeyboard() }
        if self.mouseScene !== mouseScene { self.mouseScene?.setMouseFire(false); self.mouseScene?.clearMouseAim() }
        self.highFrameRate = highFrameRate; self.paused = paused; self.spectating = spectating
        self.hardwareScene = hardwareScene; self.mouseScene = mouseScene; self.acceptsHardware = acceptsHardware
        isAccessibilityElement = !paused
        isUserInteractionEnabled = !paused && !spectating
        gameView.isUserInteractionEnabled = !paused && !spectating
        if gameView.scene !== scene { gameView.presentScene(scene) }
        if gameView.isPaused != renderingSuspended {
            scene.resetFrameClock()
            gameView.isPaused = renderingSuspended
        }
        scene.isUserInteractionEnabled = !paused && !spectating
        if paused || spectating {
            resetKeyboard(); mouseScene.setMouseFire(false); mouseScene.clearMouseAim()
            scene.resetControls(); resignFirstResponder()
        } else if acceptsHardware, window != nil, !isFirstResponder { becomeFirstResponder() }
        applyFrameRate()
    }

    private func applyFrameRate() {
        let maximum = window?.screen.maximumFramesPerSecond ?? UIScreen.main.maximumFramesPerSecond
        let requested = paused ? 30 : min(highFrameRate ? 120 : 60, maximum)
        if gameView.preferredFramesPerSecond != requested { gameView.preferredFramesPerSecond = requested }
    }

    override var canBecomeFirstResponder: Bool { acceptsHardware }
    override var keyCommands: [UIKeyCommand]? {
        guard acceptsHardware, gameScene?.onEscape != nil else { return super.keyCommands }
        let escape = UIKeyCommand(input: UIKeyCommand.inputEscape, modifierFlags: [], action: #selector(closeShowcase))
        escape.wantsPriorityOverSystemBehavior = true
        return [escape]
    }
    @objc private func closeShowcase() { gameScene?.onEscape?() }
    override func layoutSubviews() {
        super.layoutSubviews()
        if acceptsHardware, !paused, !spectating, window != nil, gameScene?.onEscape != nil, !isFirstResponder {
            becomeFirstResponder()
        }
    }
    override func didMoveToWindow() {
        super.didMoveToWindow()
        applyFrameRate()
        if window != nil { gameScene?.prepareCombatRenderer(in: gameView) }
        if window != nil && !paused && !spectating && acceptsHardware { becomeFirstResponder() }
        else { resetKeyboard(); gameScene?.resetControls() }
    }
    override func pressesBegan(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        if !setKeys(presses, down: true) { super.pressesBegan(presses, with: event) }
    }
    override func pressesEnded(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        if !setKeys(presses, down: false) { super.pressesEnded(presses, with: event) }
    }
    override func pressesCancelled(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        resetKeyboard()
        super.pressesCancelled(presses, with: event)
    }
    private func setKeys(_ presses: Set<UIPress>, down: Bool) -> Bool {
        guard acceptsHardware, let scene = hardwareScene else { return false }
        var handled = false
        let bindings = NativeInputSettings.shared.bindings
        for press in presses {
            guard let key = press.key else { continue }
            NativeHardwarePresence.shared.noteKeyboard()
            if key.keyCode == .keyboardEscape { if down { gameScene?.onEscape?() }; handled = true; continue }
            let code = key.keyCode.rawValue
            if down && !key.modifierFlags.intersection([.command, .control, .alternate]).isEmpty { continue }
            guard bindings.contains(code) || pressedKeys.contains(key.keyCode) else { continue }
            handled = true
            if down && !paused && !spectating { pressedKeys.insert(key.keyCode) }
            else { pressedKeys.remove(key.keyCode) }
        }
        if handled { scene.setKeyboardInput(bindings.input(pressed: Set(pressedKeys.map(\.rawValue)))) }
        return handled
    }

    private func resetKeyboard() { pressedKeys.removeAll(); hardwareScene?.setKeyboardInput(GameInput()) }
    private func resetHardwareControls() {
        resetKeyboard(); mouseScene?.setMouseFire(false); mouseScene?.clearMouseAim()
    }

    @objc private func pointerHover(_ gesture: UIHoverGestureRecognizer) {
        NativeHardwarePresence.shared.noteMouse()
        guard !paused, !spectating, let scene = gameScene, let target = mouseScene else { return }
        if gesture.state == .ended || gesture.state == .cancelled { target.clearMouseAim(); return }
        let point = scene.convertPoint(fromView: gesture.location(in: gameView))
        if !scene.updateMouseAim(at: point, target: target) { target.clearMouseAim() }
    }

    @objc private func pointerPress(_ gesture: UILongPressGestureRecognizer) {
        NativeHardwarePresence.shared.noteMouse()
        guard let target = mouseScene else { return }
        if gesture.state == .ended || gesture.state == .cancelled || gesture.state == .failed { target.setMouseFire(false); return }
        guard !paused, !spectating, let scene = gameScene else { return }
        let point = scene.convertPoint(fromView: gesture.location(in: gameView))
        if scene.updateMouseAim(at: point, target: target) { target.setMouseFire(true) }
    }

}


/// A secondary mouse button must not become a fire activation.
private final class PrimaryMousePressRecognizer: UILongPressGestureRecognizer {
    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
        guard event.buttonMask.contains(.primary) else { state = .failed; return }
        super.touchesBegan(touches, with: event)
    }
}
