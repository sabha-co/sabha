module ForumTestHelper
  # Builds a forum post the way U6's compose flow will: an opening message in the
  # forum plus a Rooms::Thread spawned on it, titled. Returns the post-thread.
  def create_forum_post(title: "A question", forum: rooms(:help_desk), author: users(:david))
    Current.set(user: author) do
      message = forum.messages.create!(body: title, creator: author)
      post = Rooms::Thread.find_or_create_for(message, users: [ author ])
      post.update!(name: title)
      post
    end
  end
end
