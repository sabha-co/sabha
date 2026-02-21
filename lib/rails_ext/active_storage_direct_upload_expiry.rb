# Extend direct upload URL expiry to accommodate large files on slow connections.
#
# Rails defaults to 5-minute upload URL expiry (shared with download URLs).
# For files behind Cloudflare (which buffers slow client uploads before
# proxying), 5 minutes is too short. 1 hour gives generous headroom for
# 50MB uploads on slow connections.
module ActiveStorageDirectUploadExpiry
  def service_url_for_direct_upload(expires_in: 1.hour)
    super
  end
end

ActiveSupport.on_load :active_storage_blob do
  prepend ActiveStorageDirectUploadExpiry
end
