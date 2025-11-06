class ActionText::Content::Filters
  def initialize(*filters)
    @filters = filters
  end

  def apply(content)
    filters.reduce(content) { |content, filter| filter.apply(content) }
  end

  private
    attr_reader :filters
end
