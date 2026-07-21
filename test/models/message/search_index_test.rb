require "test_helper"

class Message::SearchIndexTest < ActiveSupport::TestCase
  test "the search index exists for the current adapter after provisioning" do
    assert Message::SearchIndex.exists?

    if Message::SearchIndex.postgresql?
      # A GIN index over the tsvector column is what makes @@ queries fast.
      assert Message.connection.index_exists?(:messages, :body_search, name: "index_messages_on_body_search")
    end
  end

  test "ensure! is idempotent — re-running never recreates the index or duplicates rows" do
    message = rooms(:designers).messages.create!(
      body: "idempotent hovercraft", client_message_id: "idem", creator: users(:david)
    )

    # The index already exists (provisioned at boot), so a re-run must not raise
    # and must not re-index existing rows — the message stays findable exactly once.
    assert_nothing_raised { Message::SearchIndex.ensure! }

    assert_equal [ message ], rooms(:designers).messages.search("hovercraft")
  end
end
