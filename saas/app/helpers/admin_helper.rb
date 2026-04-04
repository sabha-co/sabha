# frozen_string_literal: true

module AdminHelper
  def sort_link(label, column)
    current = sort_column == column
    dir = current && sort_direction == "asc" ? "desc" : "asc"
    arrow = current ? (sort_direction == "asc" ? " \u2191" : " \u2193") : ""

    link_to "#{label}#{arrow}",
      url_for(request.query_parameters.merge(sort: column, direction: dir)),
      class: "txt-undecorated #{current ? '' : 'txt-muted'}",
      style: "white-space: nowrap;"
  end
end
