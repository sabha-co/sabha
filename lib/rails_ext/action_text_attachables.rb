ActiveSupport.on_load(:action_text_content) do
  class ActionText::Attachment
    class << self
      def from_node(node, attachable = nil)
        new(node, attachable || ActionText::Attachment::OpengraphEmbed.from_node(node) || attachable_from_possibly_expired_sgid(node["sgid"]) || ActionText::Attachable.from_node(node))
      end

      private
        # Our @mentions use ActionText attachments, which are signed. If someone rotates SECRET_KEY_BASE, the existing attachments become invalid.
        # This allows ignoring invalid signatures for User attachments in ActionText.
        ATTACHABLES_PERMITTED_WITH_INVALID_SIGNATURES = %w[ User ]

        def attachable_from_possibly_expired_sgid(sgid)
          if message = sgid&.split("--")&.first
            encoded_message = JSON.parse Base64.strict_decode64(message)

            decoded_gid = if data = encoded_message.dig("_rails", "data")
              data
            else
              nil
            end

            model = GlobalID.find(decoded_gid)

            model.model_name.to_s.in?(ATTACHABLES_PERMITTED_WITH_INVALID_SIGNATURES) ? model : nil
          end
        rescue ActiveRecord::RecordNotFound, JSON::ParserError, ArgumentError
          nil
        end
    end
  end
end
