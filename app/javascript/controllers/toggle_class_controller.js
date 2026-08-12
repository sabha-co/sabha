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
  }

  disconnect() {
    document.removeEventListener("keydown", this._handleKeydown)
    document.removeEventListener("turbo:click", this._handleTurboClick)
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
    // On mobile (max-width: 120ch), close the sidebar when clicking a link inside it
    // This ensures the user sees the room content after selecting it
    if (window.matchMedia("(min-width: 120ch)").matches) return
    if (!this.element.classList.contains(this.toggleClass)) return

    // Check if the clicked element is a link inside the sidebar
    const target = event.target
    const link = target.closest("a[href]")
    if (!link) return
    if (!this.element.contains(link)) return

    // Close the sidebar
    this.element.classList.remove(this.toggleClass)
  }
}
