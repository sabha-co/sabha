import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["room"]
  static values = { showStarred: { type: Boolean, default: false } }

  connect() {
    this.toggleRooms()
  }

  roomTargetConnected(element) {
    this.#toggleRoom(element)
    this.#toggleSidebarSection()
  }

  roomTargetDisconnected() {
    this.#toggleSidebarSection()
  }

  toggleRooms() {
    this.roomTargets.forEach((room) => this.#toggleRoom(room))
    this.#toggleSidebarSection()
  }

  #toggleRoom(room) {
    const isStarred = room.dataset.involvement === "everything"
    const shouldShow = this.showStarredValue ? isStarred : !isStarred

    room.toggleAttribute("hidden", !shouldShow)
    if (shouldShow && this.showStarredValue) this.#showAncestors(room)
  }

  #toggleSidebarSection() {
    const hasVisibleRoom = this.roomTargets.some((room) => !room.hidden)
    this.element.toggleAttribute("hidden", !hasVisibleRoom)
  }

  #showAncestors(room) {
    let ancestor = room.parentElement?.closest("[data-sidebar-rooms-target='room']")
    while (ancestor) {
      ancestor.removeAttribute("hidden")
      ancestor = ancestor.parentElement?.closest("[data-sidebar-rooms-target='room']")
    }
  }
}
