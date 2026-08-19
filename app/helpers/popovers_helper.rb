module PopoversHelper
  # The anchored-popover menu shell (popover_controller): a top-layer card that
  # closes when an item is activated or an in-menu form submits successfully.
  # Extra controller wiring rides in via +action+. The explicit "auto" matters:
  # a boolean attribute would render popover="popover", an invalid value that
  # falls back to manual and loses light dismiss.
  def popover_menu_tag(*css_classes, action: nil, **attributes, &block)
    base_actions = "toggle->popover#toggled click->popover#closeOnAction turbo:submit-end->popover#closeOnSubmit"

    tag.div popover: "auto", class: [ "anchored-popover", *css_classes ],
      data: { popover_target: "menu", action: [ base_actions, action ].compact.join(" ") },
      **attributes, &block
  end
end
