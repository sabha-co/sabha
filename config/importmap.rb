pin "application"

pin "@hotwired/stimulus", to: "@hotwired--stimulus.js" # @3.2.2
pin "@hotwired/stimulus-loading", to: "stimulus-loading.js"
pin "@hotwired/turbo-rails", to: "turbo.js"
pin "@rails/actioncable", to: "actioncable.esm.js"
pin "@rails/activestorage", to: "activestorage.esm.js"
pin "@anycable/web", to: "https://esm.sh/@anycable/web@1.1.0"
pin "@rails/request.js", to: "@rails--request.js" # @0.0.8
pin "lexxy", to: "lexxy.js"
pin "highlight.js", to: "highlight.js/core.js"
pin "@hotwired/hotwire-native-bridge", to: "@hotwired--hotwire-native-bridge.js" # @1.0.0

pin_all_from "app/javascript/initializers", under: "initializers"
pin_all_from "app/javascript/lib", under: "lib"
pin_all_from "app/javascript/channels", under: "channels"
pin_all_from "app/javascript/controllers", under: "controllers"
pin_all_from "app/javascript/helpers", under: "helpers"
pin_all_from "app/javascript/models", under: "models"
pin_all_from "vendor/javascript/languages", under: "languages"
