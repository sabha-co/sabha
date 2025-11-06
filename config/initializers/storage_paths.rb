Rails.application.config.after_initialize do
  %w[ db files ].each do |dir|
    Rails.root.join("storage", dir).mkpath
  end
end
