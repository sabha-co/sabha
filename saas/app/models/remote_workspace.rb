# frozen_string_literal: true

# A self-hosted Sabha community that people keep in their sabha.co list. One
# row per origin, shared by everyone who lists it, so its name and logo are
# refreshed once for all of them. It never holds anyone's session there.
class RemoteWorkspace < UntenantedRecord
  include Pairable

  # Two missed daily refreshes before an entry reads as unreachable
  UNREACHABLE_AFTER = 1.day

  # Development lists communities on http://localhost; everywhere else they
  # must be public https origins.
  class_attribute :allow_private_networks, default: Rails.env.development?

  has_many :memberships, class_name: "RemoteWorkspaceMembership", dependent: :destroy

  validates :origin, :name, presence: true

  # Nobody lists it and nothing pairs it, so there's nothing left to remember
  scope :abandoned, -> { where.missing(:memberships, :pairings).where.not(pairing_status: :active) }

  # Adding shows the name straight away; the logo follows in the background.
  after_create_commit :refresh_later, if: :logo_source_url?

  class << self
    # The community behind an address, as it describes itself right now.
    # Returns an unsaved record the first time anyone lists an origin.
    def preview(address)
      origin = RemoteWorkspace::Origin.normalize(address)
      find_by(origin: origin) || new(origin: origin).tap(&:apply_manifest)
    end

    def refresh_all_later
      find_each(&:refresh_later)
    end
  end

  def apply_manifest(manifest = RemoteWorkspace::Probe.new.manifest(origin))
    self.name = manifest.name
    self.alias_origin = manifest.alias_origin
    self.protocol_major = manifest.protocol_major
    self.logo_source_url = manifest.logo_url
    self.refreshed_at = Time.current
    self.unreachable_since = nil
  end

  def refresh_later
    RemoteWorkspace::RefreshJob.perform_later(self)
  end

  def refresh
    previous_logo_url = logo_source_url
    apply_manifest
    refresh_logo if logo_source_url != previous_logo_url || (logo_source_url && logo_data.nil?)
    save!
  rescue RemoteWorkspace::Probe::Error
    update!(unreachable_since: unreachable_since || Time.current)
  end

  def unreachable?
    unreachable_since.present? && unreachable_since <= UNREACHABLE_AFTER.ago
  end

  # What people see under the name: the origin without its scheme, keeping any
  # port, so two communities on one host can't pass for each other.
  def address
    origin.delete_prefix("https://").delete_prefix("http://")
  end

  def alias_address
    alias_origin&.delete_prefix("https://")
  end

  def logo?
    logo_data.present?
  end

  private
    def refresh_logo
      self.logo_data, self.logo_content_type = logo_source_url && RemoteWorkspace::Probe.new.logo(logo_source_url)
    end
end
