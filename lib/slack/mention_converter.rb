module Slack
  class MentionConverter
    def initialize(user_map)
      @user_map = user_map
    end

    def convert(text)
      return "" if text.blank?

      text
        .gsub(user_mention_pattern) { resolve_user_mention($1) }
        .gsub(channel_reference_pattern, '#\1')
        .gsub(url_with_text_pattern, '\2 (\1)')
        .gsub(plain_url_pattern, '\1')
        .gsub(/<!here>/, "@here")
        .gsub(/<!channel>/, "@channel")
        .gsub(/<!everyone>/, "@everyone")
    end

    private

    def user_mention_pattern
      /<@([A-Z0-9]+)(\|[^>]*)?>/
    end

    def channel_reference_pattern
      /<#[A-Z0-9]+\|([^>]+)>/
    end

    def url_with_text_pattern
      /<(https?:\/\/[^|>]+)\|([^>]+)>/
    end

    def plain_url_pattern
      /<(https?:\/\/[^>]+)>/
    end

    def resolve_user_mention(slack_user_id)
      user = @user_map[slack_user_id]
      if user
        first_name = user.name.split.first&.downcase || "user"
        "@#{first_name}"
      else
        "@unknown"
      end
    end
  end
end
