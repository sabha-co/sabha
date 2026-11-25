import { Controller } from "@hotwired/stimulus"
import { cable } from "@hotwired/turbo-rails"
import { ignoringBriefDisconnects } from "helpers/dom_helpers"

export default class extends Controller {
  static targets = [ "channel" ]
  static classes = [ "unread", "badge" ]
  static values = { stream: String }

  #disconnected = true
  #keepCurrentChannelUnread = false

  async connect() {
    // The channel-list stream is a signed pub/sub stream shared by the whole
    // account: anycable-go verifies the signature itself, so subscribing
    // costs no Rails round-trip. Missed nudges while disconnected mean a
    // stale sidebar, so a reconnect reloads the frame (#subscriptionConnected).
    // No stream value means no account yet (nothing broadcasts either).
    if (this.streamValue) {
      this.channelListChannel ??= await cable.subscribeTo({ channel: "$pubsub", signed_stream_name: this.streamValue }, {
        connected: this.#subscriptionConnected.bind(this),
        disconnected: this.#subscriptionDisconnected.bind(this),
        received: this.#channelListReceived.bind(this)
      })
    }
    this.notificationsChannel ??= await cable.subscribeTo({ channel: "UnreadNotificationsChannel" }, {
      received: this.#addBadge.bind(this)
    })
    this.involvementsChannel ??= await cable.subscribeTo({ channel: "UserInvolvementsChannel" }, {
      received: this.#updateInvolvement.bind(this)
    })
  }

  disconnect() {
    ignoringBriefDisconnects(this.element, () => {
      this.notificationsChannel?.unsubscribe()
      this.notificationsChannel = null

      this.channelListChannel?.unsubscribe()
      this.channelListChannel = null

      this.involvementsChannel?.unsubscribe()
      this.involvementsChannel = null
    })
  }

  loaded() {
    this.#readCurrentChannel()
  }

  channelTargetConnected(target) {
    if (!this.#keepCurrentChannelUnread && target.dataset.channelId == Current.channel?.id) {
      this.#readCurrentChannel()
    }
  }

  read({ detail: { channelId } }) {
    const channels = this.#findChannelTargets(channelId)

    channels.forEach(channel => {
      if (channel.dataset.sortedListPriority) {
        channel.dataset.sortedListPriority = "1"
      }
      channel.classList.remove(this.unreadClass, this.badgeClass)
      if (Current.channel?.id === channelId) {
        this.#keepCurrentChannelUnread = false
      }
      this.dispatch("read", { detail: { targetId: channelId } })
    })
  }

  #subscriptionConnected() {
    if (this.#disconnected) {
      this.#disconnected = false
      this.element.reload()
    }
  }

  #subscriptionDisconnected() {
    this.#disconnected = true
  }

  // Mark-as-unread arrives on the member's own ReadChannelsChannel (routed by
  // the read-channels controller): dot the channel even when it's the one being
  // viewed, and keep the dot through the next sidebar render.
  markUnread({ detail: { channelId, channelSize, channelUpdatedAt } }) {
    const unreadChannels = this.#findChannelTargets(channelId)

    unreadChannels.forEach(unreadChannel => {
      const sortedListTarget = unreadChannel.closest('[data-sorted-list-target]')
      if (!sortedListTarget) return

      if (sortedListTarget.dataset.sortedListPriority) {
        sortedListTarget.dataset.sortedListPriority = "0"
      }
      sortedListTarget.dataset.updatedAt = channelUpdatedAt
      sortedListTarget.dataset.size = channelSize

      unreadChannel.classList.add(this.unreadClass)
      this.#keepCurrentChannelUnread = true
    })

    this.dispatch("unread", { detail: { channelId: channelId } })
  }

  #addBadge({ channelId }) {
    const unreadChannels = this.#findChannelTargets(channelId)

    unreadChannels.forEach(unreadChannel => {
      if (Current.channel?.id != channelId) {
        unreadChannel.classList.add(this.badgeClass)
      }
    })

    this.dispatch("addBadge", { detail: { channelId: channelId } })
  }
  
  // The shared channel-list stream carries two payload kinds: a rename
  // ({channelId, sortableName}) and a touched nudge ({channelId, channelSize,
  // channelUpdatedAt, creatorId}) published once per message for the whole
  // account.
  #channelListReceived(payload) {
    if (payload.sortableName !== undefined) {
      this.#channelUpdated(payload)
    } else {
      this.#touched(payload)
    }
  }

  #channelUpdated({ channelId, sortableName }) {
    const channels = this.#findChannelTargets(channelId)

    channels.forEach(channel => {
      const sortedListTarget = channel.closest('[data-sorted-list-target]')
      if (!sortedListTarget) return

      sortedListTarget.dataset.name = sortableName
    })

    this.dispatch("renamed", { detail: { channelId: channelId } })
  }

  // A channel was touched by a new message or forum post. Refresh its sort
  // metadata for everyone; derive unread locally — no dot for the member
  // viewing the channel (they see it land) or for the creator's own clients
  // (a forum author lands on their new post, not the forum).
  #touched({ channelId, channelSize, channelUpdatedAt, creatorId }) {
    const channels = this.#findChannelTargets(channelId)

    channels.forEach(channel => {
      const sortedListTarget = channel.closest('[data-sorted-list-target]')
      if (!sortedListTarget) return

      sortedListTarget.dataset.updatedAt = channelUpdatedAt
      sortedListTarget.dataset.size = channelSize

      if (Current.channel?.id != channelId && Current.user?.id != creatorId) {
        if (sortedListTarget.dataset.sortedListPriority) {
          sortedListTarget.dataset.sortedListPriority = "0"
        }
        channel.classList.add(this.unreadClass)
      }
    })

    this.dispatch("unread", { detail: { channelId: channelId } })
  }
  
  #updateInvolvement({ channelId, involvement }) {
    const channels = this.#findChannelTargets(channelId)

    channels.forEach(channel => {
      const list_node = channel.closest('[data-type=list_node]')
      if (!list_node) return

      list_node.dataset.involvement = involvement
    })
    
    this.dispatch("involved", { detail: { channelId: channelId } })
  }

  #findChannelTargets(channelId) {
    return this.channelTargets.filter(channelTarget => channelTarget.dataset.channelId == channelId)
  }
  
  #readCurrentChannel() {
    this.read({ detail: { channelId: Current.channel?.id } })
  }
}
