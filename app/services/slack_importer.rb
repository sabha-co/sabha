require "zip"

class SlackImporter
  attr_reader :zip_path

  class ValidationResult
    attr_reader :errors, :warnings, :stats

    def initialize
      @errors = []
      @warnings = []
      @stats = {}
    end

    def valid? = errors.empty?

    def with_error(message)
      @errors << message
      self
    end

    def with_warning(message)
      @warnings << message
      self
    end

    def record_counts(users:, channels:, groups: nil, dms: nil, message_files:)
      @stats = {
        users_count: users,
        channels_count: channels,
        groups_count: groups,
        dms_count: dms,
        message_files_count: message_files,
        has_groups: groups.present?,
        has_dms: dms.present?
      }
      self
    end
  end

  def self.validate(zip_path)
    result = ValidationResult.new
    return result.with_error("File not found: #{zip_path}") unless File.exist?(zip_path)

    validate_zip_contents(zip_path, result)
    result
  end

  class << self
    private

    def validate_zip_contents(zip_path, result)
      Zip::File.open(zip_path) do |zip|
        validate_required_files(zip, result)
        return unless result.valid?

        extract_export_stats(zip, result)
        warn_if_incomplete_export(result)
      end
    rescue Zip::Error => e
      result.with_error("Invalid ZIP file: #{e.message}")
    rescue JSON::ParserError => e
      result.with_error("Invalid JSON in export: #{e.message}")
    end

    def validate_required_files(zip, result)
      %w[users.json channels.json].each do |required_file|
        result.with_error("Missing #{required_file} - this doesn't appear to be a valid Slack export") unless zip.find_entry(required_file)
      end
    end

    def extract_export_stats(zip, result)
      users = JSON.parse(zip.read("users.json"))
      channels = JSON.parse(zip.read("channels.json"))

      active_users = users.reject { |u| u["is_bot"] || u["deleted"] }
      message_files = zip.entries.count { |e| e.name.match?(%r{/.+\.json$}) && !e.name.start_with?("__MACOSX") }

      groups = zip.find_entry("groups.json") ? JSON.parse(zip.read("groups.json")) : nil
      dms = zip.find_entry("dms.json") ? JSON.parse(zip.read("dms.json")) : nil

      result.record_counts(
        users: active_users.count,
        channels: channels.count,
        groups: groups&.count,
        dms: dms&.count,
        message_files: message_files
      )
    end

    def warn_if_incomplete_export(result)
      return if result.stats[:has_groups] || result.stats[:has_dms]

      result.with_warning("This export only contains public channels. Private channels and DMs require a Slack Business+ plan to export.")
    end
  end

  def initialize(zip_path)
    @zip_path = zip_path
  end

  def import!
    Zip::File.open(zip_path) do |zip|
      context = Slack::ImportContext.new(zip)

      ActiveRecord::Base.transaction do
        Slack::UsersImporter.new(context).import
        Slack::ChannelsImporter.new(context).import
        Slack::MessagesImporter.new(context).import
        Slack::ThreadsImporter.new(context).import
      end

      context.stats
    end
  end
end
