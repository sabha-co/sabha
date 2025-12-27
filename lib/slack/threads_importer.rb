module Slack
  class ThreadsImporter
    def initialize(context)
      @context = context
    end

    def import
      thread_count = @context.thread_replies.map { |r| r[:thread_ts] }.uniq.count
      @context.log "Processing #{@context.thread_replies.count} thread replies across #{thread_count} threads..."

      replies_by_thread = @context.thread_replies.group_by { |r| r[:thread_ts] }

      replies_by_thread.each do |thread_ts, replies|
        parent = @context.message_map[thread_ts]
        unless parent
          log_skipped_thread(thread_ts, replies)
          next
        end

        thread_room = find_or_create_thread(parent, replies)
        move_replies_to_thread(thread_room, replies)
        update_counter_caches(thread_room, parent)
      end

      @context.log "Created #{@context.stats[:threads]} threads"
      log_skipped_messages_summary
    end

    private

    def find_or_create_thread(parent, replies)
      existing_thread = parent.threads.first
      return existing_thread if existing_thread

      begin
        Current.user = parent.creator

        # Include all parent room members, matching ThreadsController#new behavior
        thread_users = parent.room.users.to_a

        thread_room = Rooms::Thread.create_for(
          { parent_message_id: parent.id, creator: parent.creator },
          users: thread_users
        )

        @context.increment(:threads)
        thread_room
      ensure
        Current.user = nil
      end
    end

    def move_replies_to_thread(thread_room, replies)
      replies.each do |reply_data|
        reply = reply_data[:message]
        next if reply.room_id == thread_room.id

        reply.update_columns(room_id: thread_room.id)
        thread_room.memberships.grant_to([ reply.creator ])
      end
    end

    def update_counter_caches(thread_room, parent)
      Rooms::Thread.reset_counters(thread_room.id, :messages)
      Room.reset_counters(parent.room_id, :messages)
    end

    def log_skipped_thread(thread_ts, replies)
      reason = @context.skipped_user_messages.include?(thread_ts) ? "parent from bot/deleted user" : "parent message missing"
      @context.log "Warning: Thread skipped - #{reason} (thread_ts=#{thread_ts}, #{replies.count} replies orphaned)"
    end

    def log_skipped_messages_summary
      skipped_count = @context.skipped_user_messages.count
      return unless skipped_count > 0

      @context.log "Note: #{skipped_count} messages skipped (from bots or deleted users)"
    end
  end
end
