# frozen_string_literal: true

Gem::Specification.new do |spec|
  spec.name        = "sabha-saas"
  spec.version     = "0.2.0"
  spec.authors     = [ "Sabha" ]
  spec.email       = [ "support@sabha.co" ]
  spec.homepage    = "https://github.com/sabha-co/sabha"
  spec.summary     = "Multi-tenancy SaaS layer for Sabha"
  spec.description = "Adds multi-workspace support, GlobalIdentity authentication, and workspace isolation to Sabha"
  spec.license     = "MIT"

  spec.metadata["homepage_uri"] = spec.homepage

  spec.files = Dir.chdir(File.expand_path(__dir__)) do
    Dir["{app,config,db,lib}/**/*", "MIT-LICENSE", "Rakefile", "README.md"]
  end

  spec.required_ruby_version = ">= 3.2"

  spec.add_dependency "rails", ">= 8.0"
  spec.add_dependency "activerecord-tenanted"
end
