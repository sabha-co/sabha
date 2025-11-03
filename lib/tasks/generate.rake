namespace :generate do
  task "lines": :environment do
    room = Room.find_by(name: "Lobby")
    users = User.all

    1.upto(500) do |i|
      room.messages.create! \
        body: "Message #{i}",
        user: users.sample,
        created_at: 1.day.ago + i.minutes
    end
  end
end
