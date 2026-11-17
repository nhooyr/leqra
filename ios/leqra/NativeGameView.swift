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
                            mouseScene: mouseTargetScene ?? hardwareInputScene ?? scene)
    }
}

/// Only the primary view owns the keyboard and gamepads. Both views can receive
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
    private var controllerSeats: [ObjectIdentifier: (controller: GCController, seat: Int)] = [:]
    private var controllerObservers: [NSObjectProtocol] = []
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
        for name in [Notification.Name.GCControllerDidConnect, .GCControllerDidDisconnect] {
            controllerObservers.append(NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.syncControllers() }
            })
        }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    deinit { for observer in controllerObservers + inputObservers { NotificationCenter.default.removeObserver(observer) } }

    func configure(scene: GameScene, highFrameRate: Bool, paused: Bool, spectating: Bool,
                   hardwareScene: GameScene, acceptsHardware: Bool, mouseScene: GameScene) {
        if self.hardwareScene !== hardwareScene { resetKeyboard(); self.hardwareScene?.setGamepadInput(GameInput()) }
        if self.mouseScene !== mouseScene { self.mouseScene?.setMouseFire(false); self.mouseScene?.clearMouseAim() }
        self.highFrameRate = highFrameRate; self.paused = paused; self.spectating = spectating
        self.hardwareScene = hardwareScene; self.mouseScene = mouseScene; self.acceptsHardware = acceptsHardware
        isAccessibilityElement = !paused
        isUserInteractionEnabled = !paused && !spectating
        gameView.isUserInteractionEnabled = !paused && !spectating
        if gameView.scene !== scene { gameView.presentScene(scene) }
        scene.isUserInteractionEnabled = !paused && !spectating
        if paused || spectating {
            resetKeyboard(); mouseScene.setMouseFire(false); mouseScene.clearMouseAim()
            scene.resetControls(); resignFirstResponder()
        } else if acceptsHardware, window != nil, !isFirstResponder { becomeFirstResponder() }
        syncControllers()
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
        syncControllers()
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

    private func controllerScene(_ seat: Int) -> GameScene? {
        guard let primary = gameScene else { return nil }
        return seat == 0 ? primary : hardwareScene !== primary ? hardwareScene : nil
    }
    private func syncControllers() {
        let active = acceptsHardware && !paused && !spectating && window != nil
        let available = active ? GCController.controllers().filter { $0.extendedGamepad != nil } : []
        let connected = Set(available.map(ObjectIdentifier.init))
        for (id, record) in controllerSeats where !connected.contains(id) {
            record.controller.extendedGamepad?.valueChangedHandler = nil
            controllerScene(record.seat)?.setGamepadInput(GameInput())
            controllerSeats.removeValue(forKey: id)
        }
        guard active else { return }
        for controller in available where controllerSeats[ObjectIdentifier(controller)] == nil {
            let used = Set(controllerSeats.values.map(\.seat))
            guard let seat = (0..<2).first(where: { !used.contains($0) && controllerScene($0) != nil }) else { continue }
            controllerSeats[ObjectIdentifier(controller)] = (controller, seat)
            controller.playerIndex = seat == 0 ? .index1 : .index2
            controller.extendedGamepad?.valueChangedHandler = { [weak self] pad, _ in
                Task { @MainActor in self?.applyGamepad(pad, seat: seat) }
            }
        }
        for record in controllerSeats.values { if let pad = record.controller.extendedGamepad { applyGamepad(pad, seat: record.seat) } }
    }
    private func applyGamepad(_ pad: GCExtendedGamepad, seat: Int) {
        guard acceptsHardware, !paused, !spectating, window != nil, let scene = controllerScene(seat) else { return }
        var x = Double(pad.leftThumbstick.xAxis.value), y = -Double(pad.leftThumbstick.yAxis.value)
        if hypot(x, y) < 0.15 { x = 0; y = 0 }
        let ax = Double(pad.rightThumbstick.xAxis.value), ay = -Double(pad.rightThumbstick.yAxis.value)
        let aiming = hypot(ax, ay) >= 0.15
        scene.setGamepadInput(GameInput(
            forward: pad.dpad.up.isPressed || aiming && hypot(x, y) > 0.15,
            reverse: pad.dpad.down.isPressed,
            left: pad.dpad.left.isPressed, right: pad.dpad.right.isPressed,
            fire: pad.buttonA.isPressed || pad.rightTrigger.isPressed || pad.rightShoulder.isPressed,
            stickX: aiming ? ax : x, stickY: aiming ? ay : y, touchAim: false, aimOnly: aiming
        ))
    }
}


/// A secondary mouse button must not become a fire activation.
private final class PrimaryMousePressRecognizer: UILongPressGestureRecognizer {
    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
        guard event.buttonMask.contains(.primary) else { state = .failed; return }
        super.touchesBegan(touches, with: event)
    }
}
