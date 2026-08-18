class Everyone
  include GlobalID::Identification
  include ActionText::Attachable
  extend ActiveModel::Naming

  # Required by activerecord-tenanted gem for GlobalID serialization
  # Everyone is a singleton, not tenant-scoped
  def self.tenanted?
    false
  end

  # Stub object to satisfy avatar.attached? checks
  class NullAvatar
    def attached?
      false
    end
  end

  def self.find(id)
    new
  end

  def id
    "everyone"
  end

  def to_global_id(options = {})
    GlobalID.new("gid://sabha/Everyone/everyone")
  end

  def name
    "@everyone"
  end

  def initials
    "E"
  end

  def ascii_name
    "everyone"
  end

  def twitter_username
    nil
  end

  def linkedin_username
    nil
  end

  def avatar_url
    nil
  end

  def avatar
    NullAvatar.new
  end

  def bot?
    false
  end

  def to_param
    "everyone"
  end

  def title
    nil
  end

  def to_attachable_partial_path
    "everyone/mention"
  end

  # See User::Mentionable#attachable_content_type — the editor drops the @everyone
  # mention on edit if the regenerated node falls back to octet-stream.
  def attachable_content_type
    User::Mentionable::CONTENT_TYPE
  end

  # Rails' editor adapter renders this when loading a stored @everyone mention back
  # into the composer. The everyone/mention chip is already phrasing-safe, so the
  # editor and display share it.
  def to_editor_content_attachment_partial_path
    "everyone/mention"
  end

  def attachable_plain_text_representation(caption = nil)
    "@everyone"
  end
end
