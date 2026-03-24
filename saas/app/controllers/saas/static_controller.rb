# frozen_string_literal: true

module Saas
  class StaticController < BaseController
    allow_unauthenticated_access

    layout "marketing"

    def about
    end

    def changelog
      @changelog = parse_changelog
    end

    private

      def parse_changelog
        path = Rails.root.join("docs/CHANGELOG.md")
        return [] unless path.exist?

        sections = []
        current_section = nil
        skip_section = false

        path.readlines.each do |line|
          line = line.chomp

          if line.start_with?("### ")
            if line.include?("Multi-tenant") || line.include?("SaaS")
              skip_section = true
              current_section = nil
            else
              skip_section = false
              current_section = { heading: line.sub("### ", ""), items: [] }
              sections << current_section
            end
          elsif line.start_with?("- ") && current_section && !skip_section
            if line =~ /\A- \*\*(.+?)\*\*\s*[—–-]\s*(.+)\z/
              current_section[:items] << { title: $1, description: $2 }
            end
          end
        end

        sections.reverse
      end
  end
end
