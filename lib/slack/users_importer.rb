module Slack
  class UsersImporter
    def initialize(context)
      @context = context
    end

    def import
      users_data = @context.parse_json("users.json")
      @context.log "Found #{users_data.count} users in export"

      users_data.each do |slack_user|
        next if slack_user["is_bot"] || slack_user["deleted"]

        existing_user = find_by_slack_id(slack_user["id"])
        if existing_user
          @context.user_map[slack_user["id"]] = existing_user
          next
        end

        user = create_user(slack_user)
        @context.user_map[slack_user["id"]] = user
        @context.increment(:users)
      end

      @context.log "Imported #{@context.stats[:users]} users"
    end

    private

    def find_by_slack_id(slack_user_id)
      User.where("json_extract(preferences, '$.slack_user_id') = ?", slack_user_id).first
    end

    def create_user(slack_user)
      display_name = slack_user.dig("profile", "real_name").presence ||
                     slack_user.dig("profile", "display_name").presence ||
                     slack_user["name"]

      user = User.new(
        name: display_name.presence || "Slack User",
        email_address: nil,
        status: :active,
        role: :member,
        bio: slack_user.dig("profile", "title")
      )

      user.preferences = {
        "slack_import" => true,
        "slack_user_id" => slack_user["id"],
        "slack_username" => slack_user["name"]
      }

      user.save!(validate: false)
      user
    end
  end
end
