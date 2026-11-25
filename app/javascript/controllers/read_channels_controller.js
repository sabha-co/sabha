import { Controller } from "@hotwired/stimulus"
import { cable } from "@hotwired/turbo-rails"
import { ignoringBriefDisconnects } from "helpers/dom_helpers"

export default class extends Controller {
  async connect() {
    this.subscription ??= await cable.subscribeTo({ channel: "ReadChannelsChannel" }, {
      received: this.#received
    })
  }

  disconnect() {
    ignoringBriefDisconnects(this.element, () => {
      this.subscription?.unsubscribe()
      this.subscription = null
    })
  }

  // Read-state transitions for the current user's own channels: a bare
  // { channel_id } means read; the mark-as-unread form adds unread: true plus
  // the sidebar sort keys.
  #received = ({ channel_id, channel_size, channel_updated_at, unread }) => {
    if (unread) {
      this.dispatch("unread", { detail: { channelId: channel_id, channelSize: channel_size, channelUpdatedAt: channel_updated_at } })
    } else {
      this.dispatch("read", { detail: { channelId: channel_id } })
    }
  }
}
