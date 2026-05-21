import { Controller } from "@hotwired/stimulus"
import { patch } from "@rails/request.js"

// Handles drag-to-reorder for workspace icons in the workspace selector sidebar.
// Persists order via PATCH to /workspace_membership_order endpoint.
// Note: Drag-to-reorder is disabled on touch devices as HTML5 drag doesn't work well.
export default class extends Controller {
  static targets = ["item"]

  connect() {
    this.isTouchDevice = window.matchMedia("(hover: none) and (pointer: coarse)").matches
    this.isSaving = false
    this.pendingOrder = null
    this.draggingWorkspaceId = null
  }

  disconnect() {
    this.draggingWorkspaceId = null
    this.pendingOrder = null
  }

  // Handle new items added after connect (e.g., via Turbo Stream)
  itemTargetConnected(item) {
    if (this.isTouchDevice) {
      item.removeAttribute("draggable")
    }
  }

  // Find the currently dragged element by workspace ID (survives Turbo morphs)
  get draggedItem() {
    if (!this.draggingWorkspaceId) return null
    return this.itemTargets.find(
      el => el.dataset.workspaceId === this.draggingWorkspaceId
    )
  }

  dragstart(event) {
    if (this.isTouchDevice) return
    if (this.draggingWorkspaceId) return // Already dragging

    const item = event.currentTarget
    event.dataTransfer.effectAllowed = "move"
    event.dataTransfer.setData("text/plain", item.dataset.workspaceId)
    item.classList.add("dragging")
    this.draggingWorkspaceId = item.dataset.workspaceId
  }

  dragover(event) {
    if (this.isTouchDevice) return

    event.preventDefault()
    event.dataTransfer.dropEffect = "move"

    const target = event.target.closest("[data-workspace-sortable-target='item']")
    const draggedItem = this.draggedItem

    if (target && draggedItem && target !== draggedItem) {
      const rect = target.getBoundingClientRect()
      const midY = rect.top + rect.height / 2

      this.itemTargets.forEach(item => item.classList.remove("drag-over"))
      target.classList.add("drag-over")

      if (event.clientY < midY) {
        target.before(draggedItem)
      } else {
        target.after(draggedItem)
      }
    }
  }

  dragend(event) {
    if (this.isTouchDevice) return

    this.draggedItem?.classList.remove("dragging")
    this.itemTargets.forEach(item => item.classList.remove("drag-over"))
    this.draggingWorkspaceId = null
    this.saveOrder()
  }

  async saveOrder() {
    const workspaceIds = this.itemTargets.map(el => el.dataset.workspaceId)

    // If already saving, queue this order for after current save completes
    if (this.isSaving) {
      this.pendingOrder = workspaceIds
      return
    }

    this.isSaving = true
    try {
      const response = await patch("/workspace_membership_order", {
        body: JSON.stringify({ workspace_ids: workspaceIds }),
        contentType: "application/json"
      })

      if (!response.ok) {
        console.error("Failed to save workspace order:", response.status)
      }
    } catch (error) {
      console.error("Network error saving workspace order:", error)
    } finally {
      this.isSaving = false

      // Process any queued order change
      if (this.pendingOrder) {
        const nextOrder = this.pendingOrder
        this.pendingOrder = null
        // Only save if the order actually differs from what we just saved
        if (JSON.stringify(nextOrder) !== JSON.stringify(workspaceIds)) {
          this.saveOrder()
        }
      }
    }
  }
}
