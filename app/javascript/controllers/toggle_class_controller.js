import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static classes = ["toggle"]
  static values = {
    closeOnEscape: Boolean,
    focusTrap: Boolean,
    initialFocusSelector: String,
  }

  connect() {
    this._handleKeydown = (event) => this.#handleKeydown(event)
    document.addEventListener("keydown", this._handleKeydown)

    // Close sidebar on mobile when navigating to a new page
    this._handleTurboClick = (event) => this.#handleTurboClick(event)
    document.addEventListener("turbo:click", this._handleTurboClick)

    // Close an overlaid sidebar when pointing outside it (scrim clicks land
    // on the body, so this also serves as the scrim's dismiss action)
    this._handleOutsidePointer = (event) => this.#handleOutsidePointer(event)
    document.addEventListener("mousedown", this._handleOutsidePointer)
    document.addEventListener("touchstart", this._handleOutsidePointer, {
      passive: true,
    })
  }

  disconnect() {
    document.removeEventListener("keydown", this._handleKeydown)
    document.removeEventListener("turbo:click", this._handleTurboClick)
    document.removeEventListener("mousedown", this._handleOutsidePointer)
    document.removeEventListener("touchstart", this._handleOutsidePointer)
  }

  toggle() {
    this.element.classList.toggle(this.toggleClass)
    // When opening, move focus to initial target inside
    if (this.element.classList.contains(this.toggleClass)) {
      if (this.focusTrapValue) this.#focusInitial()
    }
  }

  #handleKeydown(event) {
    const isOpen = this.element.classList.contains(this.toggleClass)
    if (event.key === "Escape") {
      if (!this.closeOnEscapeValue || !isOpen) return
      this.element.classList.remove(this.toggleClass)
      if (this.element.id === "sidebar") {
        const toggle = document.getElementById("sidebar-toggle")
        if (toggle) toggle.focus()
      }
      return
    }

    if (event.key !== "Tab") return
    if (!this.focusTrapValue || !isOpen) return
    const focusables = this.#focusableWithin()
    if (focusables.length === 0) return
    const first = focusables[0]
    const last = focusables[focusables.length - 1]
    const active = document.activeElement
    if (!this.element.contains(active)) {
      event.preventDefault()
      first.focus()
      return
    }
    if (event.shiftKey && active === first) {
      event.preventDefault()
      last.focus()
    } else if (!event.shiftKey && active === last) {
      event.preventDefault()
      first.focus()
    }
  }

  #focusInitial() {
    const selector = this.hasInitialFocusSelectorValue
      ? this.initialFocusSelectorValue
      : undefined
    let target = selector
      ? this.element.querySelector(selector)
      : this.#focusableWithin()[0]
    if (!target && this.element.id === "sidebar") {
      target = this.element.querySelector("#room-search")
    }
    if (target && typeof target.focus === "function") {
      // Defer to next tick to respect any CSS transitions
      setTimeout(() => target.focus(), 0)
    }
  }

  #focusableWithin() {
    return Array.from(
      this.element.querySelectorAll(
        'a[href], area[href], button:not([disabled]), input:not([disabled]), select:not([disabled]), textarea:not([disabled]), [tabindex]:not([tabindex="-1"])',
      ),
    ).filter((el) => !el.hasAttribute("disabled") && el.tabIndex !== -1)
  }

  #handleTurboClick(event) {
    // When the sidebar overlays the content (drawer or expanded rail), close
    // it on navigation so the user sees the room they just picked
    if (!this.#openAsOverlay) return

    // Check if the clicked element is a link inside the sidebar
    const target = event.target
    const link = target.closest("a[href]")
    if (!link) return
    if (!this.element.contains(link)) return

    // Close the sidebar
    this.element.classList.remove(this.toggleClass)
  }

  #handleOutsidePointer(event) {
    if (!this.#openAsOverlay) return
    if (this.element.contains(event.target)) return

    this.element.classList.remove(this.toggleClass)
  }

  // Overlay modes (drawer below 834px, expanded rail below 1280px) position
  // the element fixed; when docked it's a static grid column. Keying off the
  // computed style keeps the breakpoints out of the JS.
  get #openAsOverlay() {
    return (
      this.element.classList.contains(this.toggleClass) &&
      getComputedStyle(this.element).position === "fixed"
    )
  }
}
