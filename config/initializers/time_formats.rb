# Used to match JavaScript's (new Date).getTime() for sorting
ActiveSupport::TimeFormats.register(:epoch, ->(time) { (time.to_f * 1000).to_i })
