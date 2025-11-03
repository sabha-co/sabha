module Pagination
  extend ActiveSupport::Concern

  PAGE_SIZE = 25

  included do
    scope :last_page, ->(page_size = PAGE_SIZE) { ordered.last(page_size) }
    scope :first_page, ->(page_size = PAGE_SIZE) { ordered.first(page_size) }

    scope :before, ->(record) { where("#{arel_table.name}.created_at < ?", record.created_at) }
    scope :after, ->(record) { where("#{arel_table.name}.created_at > ?", record.created_at) }

    scope :page_before, ->(record, page_size = PAGE_SIZE) { before(record).last_page(page_size) }
    scope :page_after, ->(record, page_size = PAGE_SIZE) { after(record).first_page(page_size) }

    scope :page_created_since, ->(time) { where("#{arel_table.name}.created_at > ?", time).first_page }
    scope :page_updated_since, ->(time) { where("#{arel_table.name}.updated_at > ?", time).last_page }
  end

  class_methods do
    def page_around(record)
      page_before(record, 10) + [ record ] + page_after(record, 20)
    end

    def paged?
      count > PAGE_SIZE
    end
  end
end
