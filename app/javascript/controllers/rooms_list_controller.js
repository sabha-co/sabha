import { Controller } from "@hotwired/stimulus"
import { cable } from "@hotwired/turbo-rails"
import { ignoringBriefDisconnects } from "helpers/dom_helpers"

export default class extends Controller {
  static targets = [ "room" ]
  static classes = [ "unread", "badge" ]
  static values = { stream: String }

  #disconnected = true
  #keepCurrentRoomUnread = false

  async connect() {
    // The room-list stream is a signed pub/sub stream shared by the whole
    // account: anycable-go verifies the signature itself, so subscribing
    // costs no Rails round-trip. Missed nudges while disconnected mean a
    // stale sidebar, so a reconnect reloads the frame (#channelConnected).
    // No stream value means no account yet (nothing broadcasts either).
    if (this.streamValue) {
      this.roomListChannel ??= await cable.subscribeTo({ channel: "$pubsub", signed_stream_name: this.streamValue }, {
        connected: this.#channelConnected.bind(this),
        disconnected: this.#channelDisconnected.bind(this),
        received: this.#roomListReceived.bind(this)
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

      this.roomListChannel?.unsubscribe()
      this.roomListChannel = null

      this.involvementsChannel?.unsubscribe()
      this.involvementsChannel = null
    })
  }

  loaded() {
    this.#readCurrentRoom()
    this.markCurrent()
  }

  roomTargetConnected(target) {
    if (!this.#keepCurrentRoomUnread && target.dataset.roomId == Current.room?.id) {
      this.#readCurrentRoom()
    }
    this.#markCurrentOn(target)
  }

  // The sidebar frame is turbo-permanent, so page navigations don't rerender
  // it — re-mark the current room from the fresh meta tags on every visit.
  markCurrent() {
    this.roomTargets.forEach(target => this.#markCurrentOn(target))
  }

  read({ detail: { roomId } }) {
    const rooms = this.#findRoomTargets(roomId)

    rooms.forEach(room => {
      if (room.dataset.sortedListPriority) {
        room.dataset.sortedListPriority = "1"
      }
      room.classList.remove(this.unreadClass, this.badgeClass)
      if (Current.room?.id === roomId) {
        this.#keepCurrentRoomUnread = false
      }
      this.dispatch("read", { detail: { targetId: roomId } })
    })
  }

  #channelConnected() {
    if (this.#disconnected) {
      this.#disconnected = false
      this.element.reload()
    }
  }

  #channelDisconnected() {
    this.#disconnected = true
  }

  // Mark-as-unread arrives on the member's own ReadRoomsChannel (routed by
  // the read-rooms controller): dot the room even when it's the one being
  // viewed, and keep the dot through the next sidebar render.
  markUnread({ detail: { roomId, roomSize, roomUpdatedAt } }) {
    const unreadRooms = this.#findRoomTargets(roomId)

    unreadRooms.forEach(unreadRoom => {
      const sortedListTarget = unreadRoom.closest('[data-sorted-list-target]')
      if (!sortedListTarget) return

      if (sortedListTarget.dataset.sortedListPriority) {
        sortedListTarget.dataset.sortedListPriority = "0"
      }
      sortedListTarget.dataset.updatedAt = roomUpdatedAt
      sortedListTarget.dataset.size = roomSize

      unreadRoom.classList.add(this.unreadClass)
      this.#keepCurrentRoomUnread = true
    })

    this.dispatch("unread", { detail: { roomId: roomId } })
  }

  #addBadge({ roomId }) {
    const unreadRooms = this.#findRoomTargets(roomId)

    unreadRooms.forEach(unreadRoom => {
      if (Current.room?.id != roomId) {
        unreadRoom.classList.add(this.badgeClass)
      }
    })

    this.dispatch("addBadge", { detail: { roomId: roomId } })
  }
  
  // The shared room-list stream carries two payload kinds: a rename
  // ({roomId, sortableName}) and a touched nudge ({roomId, roomSize,
  // roomUpdatedAt, creatorId}) published once per message for the whole
  // account.
  #roomListReceived(payload) {
    if (payload.sortableName !== undefined) {
      this.#roomUpdated(payload)
    } else {
      this.#touched(payload)
    }
  }

  #roomUpdated({ roomId, sortableName }) {
    const rooms = this.#findRoomTargets(roomId)

    rooms.forEach(room => {
      const sortedListTarget = room.closest('[data-sorted-list-target]')
      if (!sortedListTarget) return

      sortedListTarget.dataset.name = sortableName
    })

    this.dispatch("renamed", { detail: { roomId: roomId } })
  }

  // A room was touched by a new message or forum post. Refresh its sort
  // metadata for everyone; derive unread locally — no dot for the member
  // viewing the room (they see it land) or for the creator's own clients
  // (a forum author lands on their new post, not the forum).
  #touched({ roomId, roomSize, roomUpdatedAt, creatorId }) {
    const rooms = this.#findRoomTargets(roomId)

    rooms.forEach(room => {
      const sortedListTarget = room.closest('[data-sorted-list-target]')
      if (!sortedListTarget) return

      sortedListTarget.dataset.updatedAt = roomUpdatedAt
      sortedListTarget.dataset.size = roomSize

      if (Current.room?.id != roomId && Current.user?.id != creatorId) {
        if (sortedListTarget.dataset.sortedListPriority) {
          sortedListTarget.dataset.sortedListPriority = "0"
        }
        room.classList.add(this.unreadClass)
      }
    })

    this.dispatch("unread", { detail: { roomId: roomId } })
  }
  
  #updateInvolvement({ roomId, involvement }) {
    const rooms = this.#findRoomTargets(roomId)

    rooms.forEach(room => {
      const list_node = room.closest('[data-type=list_node]')
      if (!list_node) return

      list_node.dataset.involvement = involvement
    })
    
    this.dispatch("involved", { detail: { roomId: roomId } })
  }

  #findRoomTargets(roomId) {
    return this.roomTargets.filter(roomTarget => roomTarget.dataset.roomId == roomId)
  }

  #markCurrentOn(target) {
    if (target.dataset.roomId == Current.room?.id) {
      target.setAttribute("aria-current", "page")
    } else {
      target.removeAttribute("aria-current")
    }
  }
  
  #readCurrentRoom() {
    this.read({ detail: { roomId: Current.room?.id } })
  }
}
