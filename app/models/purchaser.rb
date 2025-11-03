class Purchaser
  def initialize
    load_configuration
  end

  def registered?
    @purchased_by.present?
  end

  def name
    @purchased_by["name"] if registered?
  end

  private
    def load_configuration
      path = Rails.root.join("config/purchased_by.yml")
      @purchased_by = YAML.load_file(path) if path.exist?
    end
end
