import PreferenceController from "lib/preference_controller"

// UI typeface: the bundled Instrument Sans webfont (default) or the platform
// system stack.
export default class extends PreferenceController {
  static key = "typeface"
  static attribute = "data-typeface"
  static onValue = "system"
  static offValue = "default"
}
