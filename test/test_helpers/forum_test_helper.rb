module ForumTestHelper
  # Builds a forum post through the canonical Rooms::Forum#post! path (a
  # Rooms::Post whose body is its first message), as the poster. Returns the post.
  def create_forum_post(title: "A question", forum: rooms(:help_desk), author: users(:david))
    Current.set(user: author) do
      forum.post!(title: title, body: title)
    end
  end
end
