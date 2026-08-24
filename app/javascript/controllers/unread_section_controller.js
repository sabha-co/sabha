import { Controller } from "@hotwired/stimulus"

// The v2.1 UNREAD section: rooms with unseen messages that are not starred.
// The server renders the initial partition (SidebarMemberships#unread vs
// #shared); after that, the same rooms-list events the other sections already
// listen to drive the moves — a room gaining unread jumps in from ROOMS, a
// read room returns there. Rows move without animation (comp), and the
// section hides itself entirely at zero via CSS (:not(:has(.room-row))).
export default class extends Controller {
  static targets = [ "count" ]

  // A message landed in a shared room this member isn't viewing: pull its row
  // out of ROOMS into here. Starred rows stay in FAVORITES (starred wins over
  // unread), so only the shared list is searched.
  moveIn({ detail: { roomId } }) {
    const node = this.#listNode(document.getElementById("shared_rooms"), roomId)
    if (!node) return

    this.element.querySelector("[data-sorted-list-target='container']")?.append(node)
    this.#refreshCount()
  }

  // The room was read: send its row back to ROOMS. Appending re-registers it
  // with that section's sorted-list controller, which re-sorts on connect.
  // rooms_list#read dispatches targetId (not roomId), so accept either key.
  moveOut({ detail }) {
    const roomId = detail.roomId ?? detail.targetId
    const node = this.#listNode(this.element, roomId)
    if (!node) return

    document.getElementById("shared_rooms")?.append(node)
    this.#refreshCount()
  }

  #listNode(scope, roomId) {
    return scope?.querySelector(`[data-room-id="${roomId}"]`)?.closest('[data-type="list_node"]') ?? null
  }

  #refreshCount() {
    if (!this.hasCountTarget) return

    const size = this.#size()
    this.countTarget.textContent = size
    this.countTarget.hidden = size === 0
  }

  #size() {
    return this.element.querySelectorAll('[data-type="list_node"]').length
  }
}
