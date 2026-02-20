module Users::FilterHelper
  def user_filter_menu_tag(&)
    tag.menu class: "flex flex-column gap margin-none pad overflow-y constrain-height",
      data: { controller: "filter" }, &
  end

  def user_filter_search_tag
    tag.input type: "search", autocorrect: "off", autocomplete: "off", "data-1p-ignore": "true",
      class: "input input--transparent full-width", placeholder: "Filter\u2026",
      data: { filter_target: "input", action: "input->filter#filter" }
  end
end
