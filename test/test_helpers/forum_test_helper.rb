module ForumTestHelper
  # Builds a forum post through the canonical Rooms::Forum#post! path (opening
  # message + titled Rooms::Thread), as the poster. Returns the post-thread.
  def create_forum_post(title: "A question", forum: rooms(:help_desk), author: users(:david))
    Current.set(user: author) do
      forum.post!(title: title, body: title)
    end
  end
end
