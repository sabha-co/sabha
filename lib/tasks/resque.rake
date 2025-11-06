task "resque:setup" do
  require File.expand_path("../../config/environment", __dir__)
end

task "resque:pool:setup" do
  ActiveRecord::Base.connection.disconnect!

  Resque::Pool.after_prefork do |job|
    ActiveRecord::Base.establish_connection
    # Redis 5.4.0+ auto-reconnects after fork, no manual reconnect needed
  end
end
