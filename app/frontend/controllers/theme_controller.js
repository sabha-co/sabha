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
    localStorage.setItem("theme", "auto")
    this.applyTheme()
    this.updateButtons()
  }

  applyTheme() {
    const theme = localStorage.getItem("theme")
    const currentTheme = document.documentElement.getAttribute("data-theme") || "light"
    const newTheme = theme === "dark" ? "dark" : (theme === "auto" ? "auto" : "light")
    const hasChanged = currentTheme !== newTheme

    const prefersReducedMotion = window.matchMedia?.("(prefers-reduced-motion: reduce)")?.matches
    const animate = hasChanged && !prefersReducedMotion

    const apply = () => {
      if (theme === "dark") {
        document.documentElement.setAttribute("data-theme", "dark")
      } else if (theme === "auto") {
        document.documentElement.removeAttribute("data-theme")
      } else {
        document.documentElement.setAttribute("data-theme", "light")
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
    const isLight = !theme || theme === "light"
    const isDark = theme === "dark"
    const isAuto = theme === "auto"

    if (this.hasLightButtonTarget) {
      this.lightButtonTarget.setAttribute("aria-selected", isLight)
    }
    if (this.hasDarkButtonTarget) {
      this.darkButtonTarget.setAttribute("aria-selected", isDark)
    }
    if (this.hasAutoButtonTarget) {
      this.autoButtonTarget.setAttribute("aria-selected", isAuto)
    }
  }
}
