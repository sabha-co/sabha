module FragmentCache
  def render_or_cached(cache, partial:, locals:)
    return cache[locals] if cache[locals].present?

    rendered_partial = render_to_string(partial:, locals:)
    cache[locals] = rendered_partial

    rendered_partial
  end
end
