import { Controller } from "@hotwired/stimulus";

export default class extends Controller {
  static targets = ["lightButton", "darkButton", "autoButton", "currentTheme"];

  connect() {
    this.#apply();
    this.#updateButtons();
  }

  setLight() {
    this.#store("light");
  }

  setDark() {
    this.#store("dark");
  }

  setAuto() {
    this.#store("auto");
  }

  // The footer toggle flips the effective appearance to an explicit choice;
  // the appearance settings' three-state control is the way back to System.
  toggle() {
    const explicit = document.documentElement.getAttribute("data-theme");
    const effectivelyDark = explicit
      ? explicit === "dark"
      : window.matchMedia("(prefers-color-scheme: dark)").matches;

    this.#store(effectivelyDark ? "light" : "dark");
  }

  #store(theme) {
    localStorage.setItem("theme", theme);

    this.#apply();
    this.#updateButtons();
  }

  #apply() {
    const theme = localStorage.getItem("theme");
    const currentTheme =
      document.documentElement.getAttribute("data-theme") || "light";
    const newTheme =
      theme === "dark" ? "dark" : theme === "auto" ? "auto" : "light";
    const hasChanged = currentTheme !== newTheme;

    const prefersReducedMotion = window.matchMedia?.(
      "(prefers-reduced-motion: reduce)",
    )?.matches;
    const animate = hasChanged && !prefersReducedMotion;

    const apply = () => {
      if (theme === "dark") {
        document.documentElement.setAttribute("data-theme", "dark");
        document.documentElement.style.colorScheme = "dark";
      } else if (theme === "auto") {
        document.documentElement.removeAttribute("data-theme");
        document.documentElement.style.colorScheme = "light dark";
      } else {
        document.documentElement.setAttribute("data-theme", "light");
        document.documentElement.style.colorScheme = "light";
      }
    };

    if (animate && document.startViewTransition) {
      document.startViewTransition(apply);
    } else {
      apply();
    }
  }

  #updateButtons() {
    const theme = localStorage.getItem("theme");

    const isLight = !theme || theme === "light";
    const isDark = theme === "dark";
    const isAuto = theme === "auto";

    if (this.hasLightButtonTarget) {
      this.lightButtonTarget.setAttribute("aria-selected", isLight);
    }
    if (this.hasDarkButtonTarget) {
      this.darkButtonTarget.setAttribute("aria-selected", isDark);
    }
    if (this.hasAutoButtonTarget) {
      this.autoButtonTarget.setAttribute("aria-selected", isAuto);
    }

    if (this.hasCurrentThemeTarget) {
      const label = isDark ? "Dark" : isAuto ? "System" : "Light";
      this.currentThemeTargets.forEach(
        (target) => (target.textContent = label),
      );
    }
  }
}
