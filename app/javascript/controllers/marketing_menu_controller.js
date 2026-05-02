import { Controller } from "@hotwired/stimulus"

// Hamburger menu for the public marketing nav. Toggles `nav-open` on the
// `.landing-nav` element, closes on outside click, Escape, or any link tap
// inside the mobile menu, and keeps `aria-expanded` on the button in sync.
export default class extends Controller {
  static targets = ["toggle", "menu"]

  connect() {
    this._handleDocumentClick = (event) => this.#handleDocumentClick(event)
    this._handleKeydown = (event) => this.#handleKeydown(event)
    document.addEventListener("click", this._handleDocumentClick)
    document.addEventListener("keydown", this._handleKeydown)
  }

  disconnect() {
    document.removeEventListener("click", this._handleDocumentClick)
    document.removeEventListener("keydown", this._handleKeydown)
  }

  toggle() {
    this.#isOpen() ? this.#close() : this.#open()
  }

  closeOnLinkClick(event) {
    if (event.target.tagName === "A") this.#close()
  }

  #open() {
    this.element.classList.add("nav-open")
    if (this.hasToggleTarget) this.toggleTarget.setAttribute("aria-expanded", "true")
  }

  #close() {
    this.element.classList.remove("nav-open")
    if (this.hasToggleTarget) this.toggleTarget.setAttribute("aria-expanded", "false")
  }

  #isOpen() {
    return this.element.classList.contains("nav-open")
  }

  #handleDocumentClick(event) {
    if (!this.element.contains(event.target)) this.#close()
  }

  #handleKeydown(event) {
    if (event.key === "Escape") this.#close()
  }
}
