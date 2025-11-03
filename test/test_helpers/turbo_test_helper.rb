module TurboTestHelper
  def assert_rendered_turbo_stream_broadcast(*streambles, action:, target:, &block)
    streams = find_broadcasts_for(*streambles)
    target = ActionView::RecordIdentifier.dom_id(*target)
    assert_select Nokogiri::HTML.fragment(streams), %(turbo-stream[action="#{action}"][target="#{target}"]), &block
  end

  private
    def find_broadcasts_for(*streambles)
      broadcasting = streambles.collect do |streamble|
        streamble.try(:to_gid_param) || streamble
      end.join(":")

      broadcasts = ActionCable.server.pubsub.broadcasts(broadcasting)
      broadcasts.collect { |b| JSON.parse(b) }.join("\n\n")
    end
end
