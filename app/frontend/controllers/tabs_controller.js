import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["tab", "panel"]
  static values = { initial: String }

  connect() {
    const initial = this.initialValue
      ? this.tabTargets.find(t => t.getAttribute("aria-controls") === `tab-${this.initialValue}`)
      : null

    this.select({ currentTarget: initial || this.tabTargets[0] })
  }

  select(event) {
    const selectedTab = event.currentTarget
    const panelId = selectedTab.getAttribute("aria-controls")

    this.tabTargets.forEach(tab => {
      const isSelected = tab === selectedTab
      tab.setAttribute("aria-selected", isSelected)
      tab.setAttribute("tabindex", isSelected ? "0" : "-1")
    })

    this.panelTargets.forEach(panel => {
      panel.hidden = panel.id !== panelId
    })
  }

  keydown(event) {
    const tabs = this.tabTargets
    const index = tabs.indexOf(event.currentTarget)

    let newIndex
    switch (event.key) {
      case "ArrowLeft":
        newIndex = (index - 1 + tabs.length) % tabs.length
        break
      case "ArrowRight":
        newIndex = (index + 1) % tabs.length
        break
      case "Home":
        newIndex = 0
        break
      case "End":
        newIndex = tabs.length - 1
        break
      default:
        return
    }

    event.preventDefault()
    tabs[newIndex].focus()
    this.select({ currentTarget: tabs[newIndex] })
  }
}
