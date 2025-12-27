module Slack
  class ImportContext
    attr_reader :zip, :stats
    attr_accessor :user_map, :channel_map, :message_map, :thread_replies, :skipped_user_messages

    def initialize(zip)
      @zip = zip
      @stats = { users: 0, rooms: 0, messages: 0, boosts: 0, threads: 0 }
      @user_map = {}
      @channel_map = {}
      @message_map = {}
      @thread_replies = []
      @skipped_user_messages = []
    end

    def file_exists?(name)
      zip.find_entry(name).present?
    end

    def parse_json(name)
      content = zip.read(name)
      JSON.parse(content)
    rescue JSON::ParserError => e
      log "Warning: Failed to parse #{name}: #{e.message}"
      []
    end

    def folder_exists?(name)
      zip.find_entry("#{name}/") || zip.entries.any? { |e| e.name.start_with?("#{name}/") }
    end

    def log(message)
      puts message unless Rails.env.test?
      Rails.logger.info("[SlackImport] #{message}")
    end

    def increment(stat, by: 1)
      @stats[stat] += by
    end

    def admin_user
      @admin_user ||= User.find_by(role: :administrator) || user_map.values.first || create_system_user
    end

    def mention_converter
      @mention_converter ||= MentionConverter.new(user_map)
    end

    private

    def create_system_user
      user = User.new(
        name: "Slack Import",
        email_address: nil,
        status: :active,
        role: :member
      )
      user.preferences = { "system_user" => true, "slack_import" => true }
      user.save!(validate: false)
      user
    end
  end
end
