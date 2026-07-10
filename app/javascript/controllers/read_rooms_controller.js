import { Controller } from "@hotwired/stimulus"
import { cable } from "@hotwired/turbo-rails"
import { ignoringBriefDisconnects } from "helpers/dom_helpers"

export default class extends Controller {
  async connect() {
    this.channel ??= await cable.subscribeTo({ channel: "ReadRoomsChannel" }, {
      received: this.#received
    })
  }

  disconnect() {
    ignoringBriefDisconnects(this.element, () => {
      this.channel?.unsubscribe()
      this.channel = null
    })
  }

  // Read-state transitions for the current user's own rooms: a bare
  // { room_id } means read; the mark-as-unread form adds unread: true plus
  // the sidebar sort keys.
  #received = ({ room_id, room_size, room_updated_at, unread }) => {
    if (unread) {
      this.dispatch("unread", { detail: { roomId: room_id, roomSize: room_size, roomUpdatedAt: room_updated_at } })
    } else {
      this.dispatch("read", { detail: { roomId: room_id } })
    }
  }
}
