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

  test "normalize reduces a query to bare word tokens and is idempotent" do
    assert_equal "full of eels", Message::SearchIndex.normalize("full-of-eels!")
    assert_equal "eels", Message::SearchIndex.normalize('"eels')
    assert_equal "", Message::SearchIndex.normalize("  -–  ")
    assert_equal "", Message::SearchIndex.normalize(nil)

    once = Message::SearchIndex.normalize("full-of-eels!")
    assert_equal once, Message::SearchIndex.normalize(once)
  end

  test "clear! empties the index, and it repopulates on the next write" do
    rooms(:designers).messages.create!(
      body: "clearable hovercraft", client_message_id: "clear", creator: users(:david)
    )
    assert_not_empty rooms(:designers).messages.search("hovercraft")

    Message::SearchIndex.clear!
    # On SQLite the shadow table is now empty; on Postgres the tsvector rides on
    # the (still-present) messages row, so clear! is a no-op and search stands.
    assert_empty rooms(:designers).messages.search("hovercraft") unless Message::SearchIndex.postgresql?

    # A subsequent write must still index, proving clear! empties without breaking
    # the index (it deletes rows, never drops the table).
    later = rooms(:designers).messages.create!(
      body: "later hovercraft", client_message_id: "later", creator: users(:david)
    )
    assert_includes rooms(:designers).messages.search("hovercraft"), later
  end
end
