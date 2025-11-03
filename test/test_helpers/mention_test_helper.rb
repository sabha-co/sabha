module MentionTestHelper
  def mention_attachment_for(name)
    user = users(name)
    attachment_body = ApplicationController.render partial: "users/mention", locals: { user: user }
    "<action-text-attachment sgid=\"#{user.attachable_sgid}\" content-type=\"application/vnd.campfire.mention\" content=\"#{attachment_body.gsub('"', '&quot;')}\"></action-text-attachment>"
  end
end
