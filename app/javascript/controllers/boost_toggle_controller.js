import { Controller } from "@hotwired/stimulus"

// A grouped reaction chip. Whether it's "mine" is decided here, client-side,
// because the chip's HTML is broadcast identically to every viewer and can't
// bake in a per-viewer boost id. Clicking submits the add form (join the
// reaction) or the remove form (drop mine), depending.
//
// The toggle is optimistic: the chip appears (or disappears) immediately, and
// the submit-end listener only cleans up when the response fails — on success
// the create/destroy streams replace the whole boosting frame, taking any
// optimistic node with it, so server truth wins for free.
export default class extends Controller {
  static targets = [ "addForm", "removeForm" ]
  static values = { content: String, boosterIds: Array }

  #optimisticChip = null
  #displayBeforeHide = null

  connect() {
    this.element.classList.toggle("boost--mine", this.#mine)
    this.#toggleButton?.setAttribute("aria-pressed", this.#mine ? "true" : "false")
  }

  toggle(event) {
    if (this.element.classList.contains("busy")) return

    // The frame replacement below destroys this focused button. On keyboard
    // activation (a synthetic click carries detail 0) mark the emoji so the
    // reaction bar can move focus to its successor; mouse users don't need it and
    // shouldn't have the actions bar popped open under them.
    if (event?.detail === 0) {
      this.element.closest("[data-controller~='reaction-bar']")
        ?.setAttribute("data-reaction-refocus", this.contentValue)
    }

    this.#mine ? this.#hide() : this.#insertChip()

    const form = this.#mine ? this.removeFormTarget : this.addFormTarget
    this.element.classList.add("busy")
    form.addEventListener("turbo:submit-end", (event) => {
      this.element.classList.remove("busy")
      if (!event.detail?.fetchResponse?.succeeded) this.#revert()
    }, { once: true })
    form.requestSubmit()
  }

  #insertChip() {
    const avatars = document.createElement("span")
    avatars.className = "boost__avatars flex-item-no-shrink"
    avatars.setAttribute("aria-hidden", "true")
    avatars.innerHTML = `<div class="boost__avatar"><img src="${Current.user.avatarUrl}" width="34" height="34" alt=""></div>`

    const content = document.createElement("span")
    content.className = "boost__content"
    content.textContent = this.contentValue

    const toggle = document.createElement("button")
    toggle.type = "button"
    toggle.className = "boost__toggle"
    // Inert until server truth replaces it; a click here would double-submit.
    toggle.disabled = true
    toggle.append(avatars, content)

    this.#optimisticChip = document.createElement("div")
    this.#optimisticChip.className = "boost boost--mine"
    this.#optimisticChip.dataset.optimistic = "true"
    this.#optimisticChip.append(toggle)
    this.element.after(this.#optimisticChip)
  }

  #hide() {
    this.#displayBeforeHide = this.element.style.display
    this.element.style.display = "none"
  }

  #revert() {
    if (this.#optimisticChip) {
      this.#optimisticChip.remove()
      this.#optimisticChip = null
    } else {
      this.element.style.display = this.#displayBeforeHide
      this.#displayBeforeHide = null
    }
  }

  get #mine() {
    return this.boosterIdsValue.includes(Current.user.id)
  }

  get #toggleButton() {
    return this.element.querySelector(".boost__toggle")
  }
}
