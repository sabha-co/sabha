# Used to match JavaScripts (new Date).getTime() for sorting
Time::DATE_FORMATS[:epoch] = ->(time) { (time.to_f * 1000).to_i }
