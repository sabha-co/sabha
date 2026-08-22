import PreferenceController from "lib/preference_controller"

// Sidebar row density: comfortable (default) or compact.
export default class extends PreferenceController {
  static key = "density"
  static attribute = "data-density"
  static onValue = "compact"
  static offValue = "comfortable"
}
