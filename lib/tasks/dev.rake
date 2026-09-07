namespace :dev do
  desc "Toggle Letter Opener email previews in development"
  task email: :environment do
    abort "dev:email is development only" unless Rails.env.development?

    marker = Rails.root.join("tmp/email-dev.txt")
    if marker.exist?
      marker.delete
      puts "Letter Opener turned off"
    else
      FileUtils.touch(marker)
      puts "Letter Opener turned on"
    end

    FileUtils.touch(Rails.root.join("tmp/restart.txt"))
    puts "Restart bin/dev if your server does not pick up tmp/restart.txt."
  end
end
