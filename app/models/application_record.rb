class ApplicationRecord < ActiveRecord::Base
  primary_abstract_class

  # Enable multi-tenant database isolation when SaaS mode is active
  # The activerecord-tenanted gem provides the `tenanted` macro
  tenanted if defined?(ActiveRecord::Tenanted) && Sabha.saas?
end
