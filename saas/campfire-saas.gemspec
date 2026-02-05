# frozen_string_literal: true

Gem::Specification.new do |spec|
  spec.name        = "campfire-saas"
  spec.version     = "0.1.0"
  spec.authors     = [ "Campfire" ]
  spec.email       = [ "support@campfire.com" ]
  spec.homepage    = "https://github.com/basecamp/campfire"
  spec.summary     = "Multi-tenancy SaaS layer for Campfire"
  spec.description = "Adds multi-workspace support, GlobalIdentity authentication, and workspace isolation to Campfire"
  spec.license     = "MIT"

  spec.metadata["homepage_uri"] = spec.homepage

  spec.files = Dir.chdir(File.expand_path(__dir__)) do
    Dir["{app,config,db,lib}/**/*", "MIT-LICENSE", "Rakefile", "README.md"]
  end

  spec.required_ruby_version = ">= 3.2"

  spec.add_dependency "rails", ">= 8.0"
  spec.add_dependency "activerecord-tenanted"
end
