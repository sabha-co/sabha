class Boost::Group < Data.define(:content, :count, :boosters, :truncated)
  Summary = Data.define(:groups, :total, :truncated)
end
