namespace :notifications do
  desc "Seed recent content and render both notification emails via letter_opener (dev only)."
  task preview: :environment do
    abort "Only runs in development." unless Rails.env.development?
    abort "Requires letter_opener delivery (config/environments/development.rb)." unless ActionMailer::Base.delivery_method == :letter_opener
    abort "SaaS mode not supported by this preview task — run with SAAS unset." if defined?(Sabha) && Sabha.respond_to?(:saas?) && Sabha.saas?

    recipient = User.active.verified.where.not(email_address: [ nil, "" ]).order(:id).first
    abort "No verified user with an email address found." unless recipient

    # Two open rooms the recipient is involved in (mentions/everything), authored
    # by someone else who's also a member. Anything else would either fail the
    # digest's qualifying-room scope or skip the predicate at delivery.
    candidate_rooms = recipient.memberships
      .where.not(involvement: %w[ invisible nothing ])
      .joins(:room)
      .where(rooms: { type: "Rooms::Open", active: true })
      .limit(2)
      .map(&:room)
    abort "Recipient has no eligible open-room memberships to seed against." if candidate_rooms.empty?

    rooms = candidate_rooms
    co_authors = User.active
      .where.not(id: recipient.id)
      .joins(:memberships)
      .where(memberships: { room_id: rooms.map(&:id) })
      .distinct
      .limit(3)
      .to_a
    abort "Need at least one other room member to author messages." if co_authors.empty?

    puts "Recipient:  ##{recipient.id} #{recipient.name} <#{recipient.email_address}>"
    puts "Rooms:      #{rooms.map { |r| "##{r.id} #{r.name}" }.join(", ")}"
    puts "Co-authors: #{co_authors.map { |u| "##{u.id} #{u.name}" }.join(", ")}"

    # Make sure the recipient registers as "away" — the missed-email predicate
    # requires the user not to be live-connected. workspace_locally_away? is
    # true when no connection rows are open, which is the default for a freshly-
    # checked-out dev session.
    recipient.notification_settings&.update!(missed_email_enabled: true, weekly_digest_subscribed: true)

    seeded_messages = []

    rooms.each_with_index do |room, room_idx|
      author = co_authors[room_idx % co_authors.size]

      5.times do |i|
        body =
          case [ room_idx, i ]
          in [ 0, 0 ] then "<div>#{mention_attachment_html(recipient)} can you take a look at this?</div>"
          in [ 0, 1 ] then "<div>Update: shipped the new dispatcher today.</div>"
          in [ 0, 2 ] then "<div>Following up — bundle delivery is now race-safe.</div>"
          in [ 1, 0 ] then "<div>Heads up everyone, freezing merges after Thursday.</div>"
          in [ 1, 1 ] then "<div>Test plan ran clean on both suites.</div>"
          in [ 1, 2 ] then "<div>#{mention_attachment_html(recipient)} thoughts on the digest copy?</div>"
          else "<div>Sample message #{i + 1} for digest preview.</div>"
          end

        message = room.messages.create!(
          body: body,
          creator: author,
          client_message_id: "notif_preview_#{room.id}_#{i}_#{SecureRandom.hex(3)}"
        )

        # Stagger created_at across the past week so the digest sees a real spread.
        message.update_column(:created_at, ((i + 1) * 6).hours.ago - room_idx.days)

        seeded_messages << message
      end

      # Bump one message to count as an @everyone mention for the digest's
      # everyone_mentions branch.
      room.messages.order(created_at: :desc).limit(1).each do |everyone_message|
        everyone_message.update_column(:mentions_everyone, true) if room_idx == 1
      end
    end

    # Pin a fresh active bundle so missed-notification items are obvious in the
    # rendered email. Discard any active bundle that's already attached.
    recipient.notification_bundles.active.find_each(&:destroy)
    bundle = recipient.open_notification_bundle!

    # Take four of the seeded messages: two mentions (first-of-each-room) plus
    # two as "direct_message" kind so both subject branches render in turn.
    items_messages = [
      seeded_messages.first,                                   # mention in room 0
      seeded_messages[5],                                      # mention in room 1
      seeded_messages[1],                                      # generic
      seeded_messages[6]                                       # generic
    ]
    item_kinds = %w[ mention mention direct_message direct_message ]

    items_messages.each_with_index do |message, i|
      Notification::BundleItem.find_or_create_by!(bundle: bundle, message: message, kind: item_kinds[i]) do |item|
        item.actor = message.creator
      end
    end

    bundle.reload

    items_for_mail = bundle.items.includes(:actor, message: [ :room, :rich_text_body ]).to_a
    MissedNotificationsMailer.bundle(bundle, items_for_mail).deliver_now
    puts "→ Missed-notification email delivered (bundle ##{bundle.id}, #{items_for_mail.size} items). Check the letter_opener tab."

    content = Notification::Digest::Content.new(recipient)
    if content.empty?
      puts "Digest content empty — qualifying rooms: #{content.send(:qualifying_room_ids).inspect}, counts: #{content.send(:counts_by_room_id).inspect}"
      abort "Could not produce a non-empty digest. The seeded messages may not satisfy ACTIVE_ROOM_MIN_MESSAGES (3)."
    end

    WeeklyDigestMailer.digest(recipient, content).deliver_now
    puts "→ Weekly digest email delivered. Check the letter_opener tab."
  end
end

private

def mention_attachment_html(user)
  attachment_body = ApplicationController.render(partial: "users/mention", locals: { user: user })
  %(<action-text-attachment sgid="#{user.attachable_sgid}" content-type="application/vnd.sabha.mention" content="#{attachment_body.gsub('"', "&quot;")}"></action-text-attachment>)
end
