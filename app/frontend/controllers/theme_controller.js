import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["lightButton", "darkButton", "autoButton"]

  connect() {
    this.applyTheme()
    this.updateButtons()
  }

  setLight() {
    localStorage.setItem("theme", "light")
    this.applyTheme()
    this.updateButtons()
  }

  setDark() {
    localStorage.setItem("theme", "dark")
    this.applyTheme()
    this.updateButtons()
  }

  setAuto() {
    localStorage.removeItem("theme")
    this.applyTheme()
    this.updateButtons()
  }

  applyTheme() {
    const theme = localStorage.getItem("theme")
    const currentTheme = document.documentElement.getAttribute("data-theme") || "auto"
    const newTheme = theme || "auto"
    const hasChanged = currentTheme !== newTheme

    const prefersReducedMotion = window.matchMedia?.("(prefers-reduced-motion: reduce)")?.matches
    const animate = hasChanged && !prefersReducedMotion

    const apply = () => {
      if (theme === "light") {
        document.documentElement.setAttribute("data-theme", "light")
      } else if (theme === "dark") {
        document.documentElement.setAttribute("data-theme", "dark")
      } else {
        document.documentElement.removeAttribute("data-theme")
      }
    }

    if (animate && document.startViewTransition) {
      document.startViewTransition(apply)
    } else {
      apply()
    }
  }

  updateButtons() {
    const theme = localStorage.getItem("theme")

    if (this.hasLightButtonTarget) {
      this.lightButtonTarget.setAttribute("aria-selected", theme === "light")
    }
    if (this.hasDarkButtonTarget) {
      this.darkButtonTarget.setAttribute("aria-selected", theme === "dark")
    }
    if (this.hasAutoButtonTarget) {
      this.autoButtonTarget.setAttribute("aria-selected", !theme)
    }
  }
}
