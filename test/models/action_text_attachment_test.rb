require "test_helper"

class ActionTextAttachmentTest < ActiveSupport::TestCase
  setup do
    @user = users(:david)
  end

  test "lookup user attachable with invalid sgid" do
    message, signature = @user.attachable_sgid.split("--")

    html = %Q(<action-text-attachment sgid="#{message}--invalid"></action-text-attachment>)
    node = ActionText::Fragment.wrap(html).find_all(ActionText::Attachment.tag_name).first

    attachment = ActionText::Attachment.from_node(node)
    assert_equal @user, attachment.attachable
  end

  test "lookup attachable with nil sgid" do
    html = %Q(<action-text-attachment></action-text-attachment>)
    node = ActionText::Fragment.wrap(html).find_all(ActionText::Attachment.tag_name).first

    attachment = ActionText::Attachment.from_node(node)
    assert_kind_of ActionText::Attachables::MissingAttachable, attachment.attachable
  end

  test "lookup invalid sgid for an attachable requiring a valid sgid" do
    # Make room instance attachable for testing purposes
    room = rooms(:pets).tap { |r| r.extend ActionText::Attachable }

    message, signature = rooms(:pets).attachable_sgid.split("--")

    html = %Q(<action-text-attachment sgid="#{message}--invalid"></action-text-attachment>)
    node = ActionText::Fragment.wrap(html).find_all(ActionText::Attachment.tag_name).first

    attachment = ActionText::Attachment.from_node(node)
    assert_kind_of ActionText::Attachables::MissingAttachable, attachment.attachable
  end
end
