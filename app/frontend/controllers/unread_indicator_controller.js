import { Controller } from "@hotwired/stimulus"

// Generic unread indicator controller that toggles classes on named targets
// based on whether elements matching their selectors exist in the sidebar.
//
// Usage:
//   data-controller="unread-indicator"
//   data-unread-indicator-indicators-value='[{"selector":".room.badge","class":"has-unread-activity","target":"activity"},{"selector":".direct.unread","class":"has-unread-dms","target":"dms"}]'
//   data-unread-indicator-target="activity" (on the activity link)
//   data-unread-indicator-target="dms" (on the dms link)
export default class extends Controller {
  static targets = ["activity", "dms"]
  static values = {
    indicators: Array
  }

  connect() {
    this.updateIndicators()

    this.observer = new MutationObserver(() => this.updateIndicators())

    const sidebarContainer = this.element.querySelector('.sidebar__container')
    if (sidebarContainer) {
      this.observer.observe(sidebarContainer, {
        attributes: true,
        attributeFilter: ['class'],
        subtree: true,
        childList: true
      })
    }
  }

  disconnect() {
    if (this.observer) {
      this.observer.disconnect()
    }
  }

  update() {
    this.updateIndicators()
  }

  updateIndicators() {
    this.indicatorsValue.forEach(indicator => {
      const target = this[`${indicator.target}Target`]
      if (!target) return

      const hasUnread = this.element.querySelectorAll(indicator.selector).length > 0
      target.classList.toggle(indicator.class, hasUnread)
    })
  }
}
