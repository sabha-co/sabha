module TurboTestHelper
  # The Action Cable stream a set of streamables broadcasts on, so tests can say
  # which stream they mean without rebuilding Turbo's naming scheme by hand.
  def broadcasting_for(*streamables)
    streamables.collect { |streamable| streamable.try(:to_gid_param) || streamable }.join(":")
  end

  def assert_rendered_turbo_stream_broadcast(*streambles, action:, target:, &block)
    streams = find_broadcasts_for(*streambles)
    target = case target
    when String, Symbol
      target.to_s
    else
      ActionView::RecordIdentifier.dom_id(*Array(target))
    end
    assert_select Nokogiri::HTML.fragment(streams), %(turbo-stream[action="#{action}"][target="#{target}"]), &block
  end

  private
    def find_broadcasts_for(*streambles)
      broadcasts = ActionCable.server.pubsub.broadcasts(broadcasting_for(*streambles))
      broadcasts.collect { |b| JSON.parse(b) }.join("\n\n")
    end
end
