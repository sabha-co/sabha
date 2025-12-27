namespace :slack do
  desc "Validate Slack export ZIP file without importing"
  task :validate, [ :zip_path ] => :environment do |_t, args|
    zip_path = validated_zip_path(args[:zip_path], task_name: "slack:validate")
    result = SlackImporter.validate(zip_path)

    print_validation_result(result)
    abort "VALIDATION_FAILED" unless result.valid?
    puts "VALIDATION_PASSED"
  end

  desc "Import Slack export from ZIP file"
  task :import, [ :zip_path ] => :environment do |_t, args|
    zip_path = validated_zip_path(args[:zip_path], task_name: "slack:import")

    unless ENV["SKIP_VALIDATION"]
      puts "Validating Slack export..."
      result = SlackImporter.validate(zip_path)

      unless result.valid?
        print_validation_result(result)
        abort
      end

      puts "✓ Valid export: #{result.stats[:users_count]} users, #{result.stats[:channels_count]} channels"
      result.warnings.each { |w| puts "  ⚠ #{w}" }
      puts ""
    end

    puts "Starting import..."
    puts ""

    stats = SlackImporter.new(zip_path).import!

    puts ""
    puts "IMPORT_COMPLETE"
    puts "IMPORT_STATS:#{stats.to_json}"
  end

  def validated_zip_path(path, task_name:)
    abort "Usage: bin/rails #{task_name}[/path/to/export.zip]" if path.blank?
    abort "File not found: #{path}" unless File.exist?(path)
    path
  end

  def print_validation_result(result)
    if result.valid?
      puts "✓ Valid Slack export"
      puts ""
      puts "Export contents:"
      puts "  Users:            #{result.stats[:users_count]}"
      puts "  Public channels:  #{result.stats[:channels_count]}"
      puts "  Private channels: #{result.stats[:groups_count] || 0}"
      puts "  Direct messages:  #{result.stats[:dms_count] || 0}"
      puts "  Message files:    #{result.stats[:message_files_count]}"

      if result.warnings.any?
        puts ""
        puts "Warnings:"
        result.warnings.each { |w| puts "  ⚠ #{w}" }
      end
      puts ""
    else
      puts "✗ Invalid Slack export"
      puts ""
      result.errors.each { |e| puts "  ERROR: #{e}" }
      puts ""
    end
  end
end
