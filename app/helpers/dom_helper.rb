module DomHelper
  def dom_prefix(*parts)
    parts.compact_blank.join("_")
  end
end
