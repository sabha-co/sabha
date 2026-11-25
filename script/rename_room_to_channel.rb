#!/usr/bin/env ruby
# Renames "room" to "channel" across the tracked tree: file contents and paths.
# Rerunnable, so a fork or an open branch can apply the same rename on its own
# files. With paths as arguments, only those tracked files are rewritten.
#
#   ruby script/rename_room_to_channel.rb            # the whole tree
#   ruby script/rename_room_to_channel.rb app/agent  # just these paths
#   ruby script/rename_room_to_channel.rb --dry-run  # report, change nothing
require "fileutils"
require "open3"

module RoomToChannel
  extend self

  SKIPPED = [
    %r{\Adb/migrate/},
    %r{\Adb/(queue_)?schema(_cache)?\.(rb|yml)\z},
    %r{\Asaas/db/},
    %r{\Avendor/},
    %r{\Anode_modules/},
    %r{(\A|/)[^/]*\.lock\z},
    %r{\Apnpm-lock\.yaml\z},
    %r{\.enc\z},
    %r{\Ascript/rename_room_to_channel\.rb\z},
    %r{\Adocs/plans/2026-11-25-001-refactor-rename-room-to-channel-plan\.md\z}
  ]

  # Words and phrases where "room" isn't ours.
  PROTECTED = [
    /headroom/i, /\bbrooms?\b/i, /roomier/i, /roomy/i, /classrooms?/i, /mushrooms?/i,
    /bathrooms?/i, /showrooms?/i, /boardrooms?/i,
    /\b(?:breathing|wiggle|elbow|leg) room\b/i,
    /\broom (?:to (?:breathe|grow|read|spare)|for (?:error|improvement|growth))\b/i,
    /\bgive it room\b/i
  ]

  # Applied before the plain swap. Action Cable already owns "Channel", so the
  # base class for presence and typing would otherwise be ChannelChannel.
  SPECIAL = {
    "RoomChannel" => "ChannelScopedChannel",
    "room_channel" => "channel_scoped_channel"
  }

  def rename(text)
    kept = []
    text = PROTECTED.reduce(text) do |result, pattern|
      result.gsub(pattern) { kept << $&; "\u0000KEPT#{kept.size - 1}\u0000" }
    end

    text = SPECIAL.reduce(text) { |result, (from, to)| result.gsub(from, to) }
    text = text.gsub(/room/i) do |match|
      if match == "ROOM" then "CHANNEL"
      elsif match.start_with?("R") then "Channel"
      else "channel"
      end
    end

    text.gsub(/\u0000KEPT(\d+)\u0000/) { kept[$1.to_i] }
  end

  def run(paths, dry_run: false)
    files = tracked(paths).reject { |path| SKIPPED.any? { |pattern| path.match?(pattern) } }
    rewritten = files.count { |path| rewrite(path, dry_run:) }
    moved = files.select { |path| path.match?(/room/i) }.count { |path| move(path, dry_run:) }

    puts "#{dry_run ? "Would rewrite" : "Rewrote"} #{rewritten} files, #{dry_run ? "would move" : "moved"} #{moved}"
  end

  private
    def tracked(paths)
      out, status = Open3.capture2("git", "ls-files", "-z", "--", *paths)
      abort "git ls-files failed" unless status.success?
      out.split("\u0000").select { |path| File.file?(path) && !File.symlink?(path) }
    end

    def rewrite(path, dry_run:)
      bytes = File.binread(path)
      return false if bytes.include?("\u0000") || !bytes.dup.force_encoding("UTF-8").valid_encoding?

      text = bytes.force_encoding("UTF-8")
      renamed = rename(text)
      return false if renamed == text

      File.binwrite(path, renamed) unless dry_run
      true
    end

    def move(path, dry_run:)
      destination = rename(path)
      return false if destination == path
      abort "#{destination} already exists (from #{path})" if File.exist?(destination)

      unless dry_run
        FileUtils.mkdir_p(File.dirname(destination))
        system("git", "mv", path, destination, exception: true)
      end
      true
    end
end

dry_run = ARGV.delete("--dry-run")
RoomToChannel.run(ARGV, dry_run: !!dry_run)
