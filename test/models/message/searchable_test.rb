require "test_helper"

class Message::SearchableTest < ActiveSupport::TestCase
  test "message body is indexed and searchable" do
    message = rooms(:designers).messages.create! body: "My hovercraft is full of eels", client_message_id: "earth", creator: users(:david)
    assert_equal [ message ], rooms(:designers).messages.search("eel")

    message.update! body: "My hovercraft is full of sharks"
    assert_equal [ message ], rooms(:designers).messages.search("sharks")

    message.destroy!
    assert_equal [], rooms(:designers).messages.search("sharks")
  end

  test "search results are returned in message order" do
    messages = [ "first cat", "second cat", "third cat", "cat cat cat" ].map do |body|
      rooms(:designers).messages.create! body: body, client_message_id: body, creator: users(:david)
    end

    assert_equal messages, rooms(:designers).messages.search("cat")
  end

  test "rich text body is converted to plain text for indexing" do
    message = rooms(:designers).messages.create! body: "<span>My hovercraft is full of eels</span>", client_message_id: "earth", creator: users(:david)

    assert_equal [], rooms(:designers).messages.search("span")
    assert_equal [ message ], rooms(:designers).messages.search("eel")
  end

  test "search stems terms so run matches running" do
    message = rooms(:designers).messages.create! body: "we are running late", client_message_id: "stem", creator: users(:david)

    # porter on SQLite, the english config on Postgres — both stem running to run.
    assert_equal [ message ], rooms(:designers).messages.search("run")
  end

  test "stopword-only queries diverge by engine — the one documented difference" do
    message = rooms(:designers).messages.create! body: "who goes there", client_message_id: "stop", creator: users(:david)

    if Message::SearchIndex.postgresql?
      # Postgres's english config strips stopwords, so plainto_tsquery('english', 'who')
      # is empty and matches nothing.
      assert_equal [], rooms(:designers).messages.search("who")
    else
      # FTS5's porter tokenizer keeps stopwords, so "who" is indexed and matches.
      assert_equal [ message ], rooms(:designers).messages.search("who")
    end
  end
end
