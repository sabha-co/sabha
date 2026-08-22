import { Controller } from "@hotwired/stimulus"
import { post, destroy } from "@rails/request.js"
import { normalize } from "lib/autocomplete/utils"

export default class extends Controller {
  static values = { membersUrl: String, availableUsers: Array }
  static targets = [ "input", "error" ]

  search() {
    const query = this.hasInputTarget ? this.inputTarget.value.trim() : ""

    this.#clearError()
    this.#clearSearchResults()

    if (query.length >= 2) {
      this.#renderMatches(query)
    }
  }

  async toggle(event) {
    const checkbox = event.target
    const item = checkbox.closest("[data-filter-target='item']")
    const userId = checkbox.value

    this.#clearError()

    if (checkbox.checked) {
      await this.#addMember(userId, item, checkbox)
    } else {
      await this.#removeMember(userId, item, checkbox)
    }
  }

  async #addMember(userId, item, checkbox) {
    item.removeAttribute("data-filter-default")
    item.removeAttribute("data-search-result")

    try {
      const response = await post(this.membersUrlValue, {
        body: JSON.stringify({ user_id: userId }),
        contentType: "application/json",
        responseKind: "turbo-stream"
      })

      if (!response.ok) {
        checkbox.checked = false
        item.setAttribute("data-filter-default", "hidden")
      } else {
        this.#removeFromAvailable(userId)
        item.remove()
      }
    } catch {
      checkbox.checked = false
      item.setAttribute("data-filter-default", "hidden")
    }
  }

  async #removeMember(userId, item, checkbox) {
    item.setAttribute("data-filter-default", "hidden")

    try {
      const response = await destroy(`${this.membersUrlValue}/${userId}`, {
        responseKind: "turbo-stream"
      })

      if (!response.ok) {
        checkbox.checked = true
        item.removeAttribute("data-filter-default")
        this.#showError("Someone has to stay in the room.")
      }
    } catch {
      checkbox.checked = true
      item.removeAttribute("data-filter-default")
      this.#showError("Couldn't remove them. Try again.")
    }
  }

  #renderMatches(query) {
    const normalizedQuery = normalize(query.toLowerCase())
    const matches = this.availableUsersValue.filter(user =>
      normalize(user.name.toLowerCase()).includes(normalizedQuery)
    ).slice(0, 20)

    const menu = this.element.querySelector("menu")
    matches.forEach(user => {
      menu.insertAdjacentHTML("beforeend", this.#userHTML(user))
    })
  }

  #clearSearchResults() {
    this.element.querySelectorAll("[data-search-result]").forEach(el => el.remove())
  }

  #removeFromAvailable(userId) {
    this.availableUsersValue = this.availableUsersValue.filter(u => u.id !== parseInt(userId))
  }

  #showError(message) {
    if (!this.hasErrorTarget) return
    this.errorTarget.textContent = message
    this.errorTarget.hidden = false
  }

  #clearError() {
    if (this.hasErrorTarget) this.errorTarget.hidden = true
  }

  #userHTML(user) {
    const name = this.#escapeHTML(user.name)
    const initials = user.name.split(" ").map(w => w[0]).join("").slice(0, 2).toUpperCase()

    return `<li class="flex align-center gap margin-none" data-filter-target="item" data-search-result>
      <figure class="avatar flex-item-no-shrink" style="--avatar-size: 4ch;">
        <span class="btn avatar" title="${name}" style="background: var(--color-border); display: grid; place-items: center; font-size: 0.7em;">${initials}</span>
      </figure>
      <div class="min-width">
        <div class="overflow-ellipsis fill-shade"><strong>${name}</strong></div>
      </div>
      <hr class="separator" aria-hidden="true">
      <label class="switch flex-item-no-shrink">
        <input type="checkbox" value="${user.id}" class="switch__input" data-action="change->member-toggle#toggle">
        <span class="switch__btn round"></span>
        <span class="for-screen-reader">Give ${name} access to this room</span>
      </label>
    </li>`
  }

  #escapeHTML(str) {
    const div = document.createElement("div")
    div.textContent = str
    return div.innerHTML
  }
}
