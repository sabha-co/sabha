import PreferenceController from "lib/preference_controller"

// Sidebar skin: dark Contrast against the room (default) or Match the page
// surface. The contrast scope in sidebar.css is gated on the page NOT being in
// match mode, so stamping data-sidebar="match" on <html> drops the scope.
export default class extends PreferenceController {
  static key = "sidebar"
  static attribute = "data-sidebar"
  static onValue = "match"
  static offValue = "contrast"
}
