import { Controller } from "@hotwired/stimulus"

const TRANSITION_DURATION = 300

export default class extends Controller {
  static targets = ["frame", "panel"]
  static values = { storageKey: String }

  connect() {
    this.frameTarget.addEventListener("turbo:before-fetch-request", this.#onFetchStart)
    this.frameTarget.addEventListener("turbo:frame-load", this.#onFrameLoad)
    document.addEventListener("click", this.#onTriggerClick, true)
    this.#restore()
  }

  disconnect() {
    this.frameTarget.removeEventListener("turbo:before-fetch-request", this.#onFetchStart)
    this.frameTarget.removeEventListener("turbo:frame-load", this.#onFrameLoad)
    document.removeEventListener("click", this.#onTriggerClick, true)
    clearTimeout(this.#closeTimer)
    this.#dismissPending()
  }

  open({ focus = true } = {}) {
    clearTimeout(this.#closeTimer)
    const generation = ++this.#openGeneration
    this.panelTarget.hidden = false
    this.panelTarget.setAttribute("aria-label", { roster: "Room info", thread: "Thread", forum: "Post" }[this.#kind] || "Room info")
    this.#syncTriggers(this.#kind === "roster")
    if (this.#kind === "roster" && this.#docked) this.#remember(true)
    requestAnimationFrame(() => requestAnimationFrame(() => {
      if (generation !== this.#openGeneration || !this.panelTarget.isConnected) return
      document.body.classList.add("thread-panel-open")
      if (focus) {
        const title = this.panelTarget.querySelector(".thread-panel__title") || this.panelTarget.querySelector(".thread-panel__header")
        title?.setAttribute("tabindex", "-1")
        title?.focus({ preventScroll: true })
      }
    }))
  }

  close() {
    if (this.#kind === "roster") this.#remember(false)
    this.#dismissPending()
    this.#syncTriggers(false)
    document.body.classList.remove("thread-panel-open")
    const opener = this.#opener?.isConnected && this.#opener.getClientRects().length ? this.#opener : this.#visibleTrigger
    opener?.focus({ preventScroll: true })
    clearTimeout(this.#closeTimer)
    this.#closeTimer = setTimeout(() => this.#teardown(), TRANSITION_DURATION)
  }

  closeOnEscape(event) {
    if (event.key !== "Escape" || !this.#isOpen) return
    const popup = this.panelTarget.querySelector(":popover-open")
    if (popup) {
      event.preventDefault()
      popup.hidePopover()
      popup.closest('[data-controller~="popover"]')?.querySelector('[data-popover-target="trigger"]')?.focus({ preventScroll: true })
    } else if (!event.defaultPrevented) {
      event.preventDefault()
      this.close()
    }
  }

  closeOnNavigation() {
    this.#dismissPending()
    clearTimeout(this.#closeTimer)
    document.body.classList.remove("thread-panel-open")
    this.#syncTriggers(false)
    this.#teardown()
  }

  #closeTimer
  #openGeneration = 0
  #staleDismiss = false
  #restoring = false
  #opener

  get #isOpen() { return document.body.classList.contains("thread-panel-open") }
  get #kind() { return this.frameTarget.querySelector("[data-panel-kind]")?.dataset.panelKind }
  get #docked() { return matchMedia("(min-width: 1160px)").matches }
  get #triggers() { return Array.from(document.querySelectorAll("[data-room-info-trigger]")) }
  get #visibleTrigger() { return this.#triggers.find(trigger => trigger.getClientRects().length) }

  #onTriggerClick = (event) => {
    if (event.button !== 0 || event.metaKey || event.ctrlKey || event.shiftKey || event.altKey) return
    const link = event.target.closest('a[data-turbo-frame="thread_panel_frame"]')
    if (!link) return
    this.#opener = link
    if (link.hasAttribute("data-room-info-trigger") && this.#isOpen && this.#kind === "roster") {
      event.preventDefault()
      event.stopPropagation()
      this.close()
    }
  }

  #onFetchStart = (event) => {
    if (event.target !== this.frameTarget) return
    clearTimeout(this.#closeTimer)
    this.#staleDismiss = false
  }

  #onFrameLoad = (event) => {
    if (event.target !== this.frameTarget || this.#staleDismiss) return
    this.open({ focus: !this.#restoring })
    this.#restoring = false
  }

  #syncTriggers(expanded) {
    this.#triggers.forEach(trigger => trigger.setAttribute("aria-expanded", expanded))
  }

  #remember(open) {
    try {
      if (open) localStorage.setItem(this.storageKeyValue, "open")
      else localStorage.removeItem(this.storageKeyValue)
    } catch { /* Storage can be unavailable in private browser contexts. */ }
  }

  #restore() {
    if (!this.#docked || this.frameTarget.hasAttribute("src") || !this.#visibleTrigger) return
    try {
      if (localStorage.getItem(this.storageKeyValue) !== "open") return
    } catch { return }
    this.#restoring = true
    this.frameTarget.src = this.#visibleTrigger.href
  }

  #dismissPending() {
    this.#openGeneration++
    this.#staleDismiss = true
  }

  #teardown() {
    this.panelTarget.hidden = true
    this.frameTarget.innerHTML = ""
    this.frameTarget.removeAttribute("src")
  }
}
