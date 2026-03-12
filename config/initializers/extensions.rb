Dir["#{Rails.root}/lib/helpers/*"].each { |path| require "helpers/#{File.basename(path, '.rb')}" }

# ActionText::Content::Filter and ::Filters are base classes for files in app/helpers/content_filters/.
# They must be defined before Zeitwerk eager-loads those files (which happens before after_initialize).
# Loading only these two early is safe — they don't pull in ActionMailer/ActiveJob prematurely.
ActiveSupport.on_load(:action_text_content) do
  require "rails_ext/filter"
  require "rails_ext/filters"
end

# All other rails_ext files are deferred until after initialization to avoid premature framework
# loading warnings introduced by Rails PR #56201 (https://github.com/rails/rails/pull/56201).
# These files only reference deferred constants inside method bodies (not at class scope),
# so they work fine loading after eager load.
Rails.application.config.after_initialize do
  %w[ action_text_attachables actiontext_opengraph_embeds active_storage_analyze_job_suppress_broadcasts active_storage_direct_upload_expiry string ].each do |name|
    require "rails_ext/#{name}"
  end
end
