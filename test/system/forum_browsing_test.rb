require "application_system_test_case"

# Regression wall for the forum room the v2 reskin restyles (post gallery, not a
# message stream). Asserts a forum surfaces its posts, through the post title
# text, so it survives the gallery reskin.
class ForumBrowsingTest < ApplicationSystemTestCase
  include ForumTestHelper

  setup do
    @post = create_forum_post(title: "How do I reset my password?")
    rooms(:help_desk).memberships.grant_to(users(:david))   # auto_join memberships aren't in fixtures
    sign_in "david@37signals.com"
  end

  test "a forum room shows its posts" do
    visit room_url(rooms(:help_desk))   # help_desk is a Rooms::Forum
    dismiss_pwa_install_prompt

    assert_text "How do I reset my password?"
  end
end
