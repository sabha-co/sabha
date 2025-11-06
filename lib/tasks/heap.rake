require "objspace"

namespace :heap do
  desc "Dump the entire Ruby heap to a JSON file"
  task dump: :environment do
    dump = ObjectSpace.dump_all
    puts "Heap dump written to #{dump.path}"
  end
end
