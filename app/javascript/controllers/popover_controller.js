import { Controller } from "@hotwired/stimulus"

const VIEWPORT_MARGIN = 12
const TRIGGER_GAP = 6

// Anchored popover: a menu rendered in the browser's top layer ([popover]),
// positioned from its trigger's rect — no scroll container, containment root
// or z-index stack can clip it. Light dismiss (outside click, Esc) comes from
// popover="auto"; this controller adds the anchoring math (flip above when the
// menu won't fit below, clamp 12px inside the viewport), right-click open on
// an enclosing row, and close-on-scroll so a scrolled trigger never leaves its
// menu floating detached.
export default class extends Controller {
  static targets = [ "trigger", "menu" ]
  static values = {
    // "bottom-end" right-aligns the menu to the trigger (the ⋯ menus);
    // "bottom-start" left-aligns it (profile cards).
    placement: { type: String, default: "bottom-end" },
    // Optional ancestor selector; right-clicking anywhere on it opens the menu.
    row: String
  }

  connect() {
    if (this.hasRowValue) {
      this.rowElement = this.element.closest(this.rowValue)
      this.rowElement?.addEventListener("contextmenu", this.openFromContextMenu)
    }
  }

  disconnect() {
    this.rowElement?.removeEventListener("contextmenu", this.openFromContextMenu)
    clearTimeout(this.openTimer)
    this.#stopClosingOnScroll()
  }

  toggle() {
    this.menuTarget.togglePopover()
  }

  close() {
    if (this.#open) this.menuTarget.hidePopover()
  }

  openFromContextMenu = (event) => {
    event.preventDefault()
    // contextmenu fires mid-gesture (between right press and release); opening
    // immediately lets light dismiss read the trailing pointerup — outside the
    // just-opened menu — as an outside press and close it again. Open after
    // the gesture finishes.
    if (!this.#open) this.openTimer = setTimeout(() => this.menuTarget.showPopover(), 0)
  }

  // The popover's own `toggle` event — fires for light dismiss and our calls alike,
  // so open/closed side effects live here and can't drift per entry point.
  toggled(event) {
    const open = event.newState === "open"
    this.triggerTarget.setAttribute("aria-expanded", open)

    if (open) {
      this.#loadLazyFrame()
      this.#place()
      this.#closeOnScroll()
    } else {
      this.menuTarget.classList.remove("anchored-popover--placed")
      this.#stopClosingOnScroll()
    }
  }

  // Lazily-loaded content (the quick profile card) lands after placement and
  // changes the menu's height, so re-run the math it was placed with.
  reposition() {
    if (this.#open) this.#place()
  }

  // Menu semantics: activating any item dismisses the menu
  closeOnAction(event) {
    if (event.target.closest("a[href], button")) this.close()
  }

  closeOnSubmit(event) {
    if (event.detail.success) this.close()
  }

  // Frames marked with data-turbo-frame-src load on first open, not page load
  #loadLazyFrame() {
    const frame = this.menuTarget.querySelector("turbo-frame[data-turbo-frame-src]")
    if (frame) {
      frame.src = frame.dataset.turboFrameSrc
      delete frame.dataset.turboFrameSrc
    }
  }

  // The popover `toggle` event is delivered asynchronously, so the menu could
  // paint once before this runs — it stays visibility:hidden until the placed
  // class lands (popups.css).
  #place() {
    const trigger = this.triggerTarget.getBoundingClientRect()
    const menu = this.menuTarget.getBoundingClientRect()
    const alignEnd = this.placementValue.endsWith("end")

    const inline = this.#clamp(alignEnd ? trigger.right - menu.width : trigger.left,
      window.innerWidth - menu.width)

    const flipped = trigger.bottom + TRIGGER_GAP + menu.height + VIEWPORT_MARGIN > window.innerHeight
    const block = this.#clamp(flipped ? trigger.top - TRIGGER_GAP - menu.height : trigger.bottom + TRIGGER_GAP,
      window.innerHeight - menu.height)

    this.menuTarget.style.insetInlineStart = `${inline}px`
    this.menuTarget.style.insetBlockStart = `${block}px`
    this.menuTarget.style.transformOrigin = `${flipped ? "bottom" : "top"} ${alignEnd ? "right" : "left"}`
    this.menuTarget.classList.add("anchored-popover--placed")
  }

  #clamp(position, edge) {
    return Math.min(Math.max(position, VIEWPORT_MARGIN), edge - VIEWPORT_MARGIN)
  }

  #closeOnScroll() {
    addEventListener("scroll", this.#scrolled, { capture: true, passive: true })
  }

  #stopClosingOnScroll() {
    removeEventListener("scroll", this.#scrolled, { capture: true })
  }

  #scrolled = (event) => {
    if (!this.menuTarget.contains(event.target)) this.close()
  }

  get #open() {
    return this.menuTarget.matches(":popover-open")
  }
}
