import { Controller } from "@hotwired/stimulus"

// Shared base for per-device, two-state appearance preferences: a value stored
// in localStorage and reflected as a data-* attribute on <html>, wired to a
// two-button segmented control (setOn/setOff actions, onButton/offButton
// targets). Subclasses declare the storage key, the html attribute, and the
// on/off values — nothing else. The pre-paint script in
// layouts/_theme_preference mirrors the "on" stamping so nothing flashes on load.
//
// Theme is deliberately NOT built on this — it has three states, color-scheme
// handling, and view transitions of its own.
export default class extends Controller {
  static targets = ["onButton", "offButton"]

  connect() {
    this.#apply()
    this.#updateButtons()
  }

  setOn() {
    this.#store(this.constructor.onValue)
  }

  setOff() {
    this.#store(this.constructor.offValue)
  }

  #store(value) {
    localStorage.setItem(this.constructor.key, value)
    this.#apply()
    this.#updateButtons()
  }

  #apply() {
    if (this.#on) {
      document.documentElement.setAttribute(this.constructor.attribute, this.constructor.onValue)
    } else {
      document.documentElement.removeAttribute(this.constructor.attribute)
    }
  }

  #updateButtons() {
    if (this.hasOnButtonTarget) {
      this.onButtonTarget.setAttribute("aria-selected", this.#on)
    }
    if (this.hasOffButtonTarget) {
      this.offButtonTarget.setAttribute("aria-selected", !this.#on)
    }
  }

  get #on() {
    return localStorage.getItem(this.constructor.key) === this.constructor.onValue
  }
}
