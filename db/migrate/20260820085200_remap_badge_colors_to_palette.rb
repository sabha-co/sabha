class RemapBadgeColorsToPalette < ActiveRecord::Migration[8.2]
  def up
    Badge.reset_column_information

    Badge.find_each do |badge|
      snapped = Badge.nearest_palette_color(badge.color)
      badge.update_column(:color, snapped) unless badge.color == snapped
    end
  end

  def down
    # One-way data normalisation — the original off-palette hues aren't recorded.
  end
end
