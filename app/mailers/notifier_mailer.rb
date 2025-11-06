class NotifierMailer < ApplicationMailer
  include ActionView::Helpers::TextHelper
  include RoomsHelper

  helper_method :room_display_name

  MAX_MENTIONS_COUNT = 10
  MIN_MENTIONS_TO_WRAP = 3

  def unread_mentions(user, messages)
    @user = user
    @total_messages_count = messages.count
    messages_to_include_count = if @total_messages_count > MAX_MENTIONS_COUNT
                                  [ @total_messages_count - MIN_MENTIONS_TO_WRAP, MAX_MENTIONS_COUNT ].min
    else
      @total_messages_count
    end
    @messages = messages.first(messages_to_include_count)
    @more_mentions_count = [ @total_messages_count - messages_to_include_count, 0 ].max

    mail(to: @user.email_address, subject: "You have #{pluralize(messages.size, "unread mention")}")
  end
end
