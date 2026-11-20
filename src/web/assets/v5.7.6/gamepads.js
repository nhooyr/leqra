/* Browser controller mapping shared by the finite arena, Infinity and practice. */
;(function (root, factory) {
  const api = factory()
  if (typeof module === "object" && module.exports) module.exports = api
  else root.leqraGamepads = api
})(globalThis, function () {
  "use strict"

  function stick(axes, offset) {
    const x = axes[offset] || 0,
      y = axes[offset + 1] || 0
    const length = Math.hypot(x, y)
    if (length < 0.15) return [0, 0]
    const scale = Math.min(1, 1 / length)
    return [x * scale, y * scale]
  }

  function readControls(pad) {
    const down = (index) => pad.buttons[index]?.pressed || pad.buttons[index]?.value > 0.3
    const [x, y] = stick(pad.axes, 0),
      [aimX, aimY] = stick(pad.axes, 2)
    const aiming = aimX !== 0 || aimY !== 0,
      moving = x !== 0 || y !== 0
    const reverse = !!down(13)
    const input = {
      forward: !!down(12) || (aiming && moving && !reverse),
      reverse,
      left: !!down(14),
      right: !!down(15),
      fire: !!(down(0) || down(5) || down(7)),
      stickX: aiming ? aimX : x,
      stickY: aiming ? aimY : y,
      aimOnly: aiming,
    }
    return {
      input,
      active: aiming || moving || input.forward || reverse || input.left || input.right || input.fire,
      menu: !!down(9),
    }
  }

  function merge(input, pad, touchSteering = false) {
    if (!pad) return input
    input.forward ||= pad.forward
    input.reverse ||= pad.reverse
    input.left ||= pad.left
    input.right ||= pad.right
    input.fire ||= pad.fire
    if (!touchSteering) {
      if (pad.stickX || pad.stickY) {
        input.stickX = pad.stickX
        input.stickY = pad.stickY
        input.aimOnly = pad.aimOnly
        input.snapAim = input.touchAim = false
      } else if (pad.left || pad.right) {
        input.stickX = input.stickY = 0
        input.aimOnly = input.snapAim = input.touchAim = false
      }
    }
    return input
  }

  class Gamepads {
    constructor() {
      this.slots = [null, null]
      this.inputs = [null, null]
    }

    clear() {
      this.inputs.fill(null)
      for (const slot of this.slots) if (slot) slot.armed = false
    }

    sample(devices, context, primary, secondary, canPause) {
      const pads = Array.from(devices || []).filter((pad) => pad?.connected && pad.mapping === "standard")
      if (!pads.length && !this.slots.some(Boolean)) return false
      for (let i = 0; i < this.slots.length; i++) {
        const slot = this.slots[i]
        if (slot && !pads.some((pad) => pad.index === slot.index && pad.id === slot.id)) this.slots[i] = null
      }
      for (const pad of pads) {
        if (this.slots.some((slot) => slot?.index === pad.index)) continue
        const empty = this.slots.indexOf(null)
        if (empty < 0) break
        this.slots[empty] = {
          index: pad.index,
          id: pad.id,
          menu: !!pad.buttons[9]?.pressed,
          route: "",
          armed: false,
        }
      }
      this.inputs.fill(null)
      let pause = false
      for (const [index, slot] of this.slots.entries()) {
        if (!slot) continue
        const pad = pads.find((pad) => pad.index === slot.index),
          controls = readControls(pad)
        let seat = -1
        if (primary && secondary) seat = index
        else if (primary && (index === 0 || !this.slots[0])) seat = 0
        else if (secondary && (index === 1 || !this.slots[1])) seat = 1
        if (canPause && seat >= 0 && controls.menu && !slot.menu) pause = true
        slot.menu = controls.menu

        const route = context && seat >= 0 ? context + ":" + seat : ""
        if (route !== slot.route) slot.armed = false
        slot.route = route
        if (!route) continue
        if (slot.armed && controls.active) this.inputs[seat] = controls.input
        if (!controls.active) slot.armed = true
      }
      return pause
    }
  }

  return Object.freeze({ Gamepads, merge })
})
