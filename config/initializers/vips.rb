# Disable libvips's "unfuzzed" loaders and savers (CVE-2026-66066).
#
# libvips marks the operations it considers unsafe for untrusted content as unfuzzed — several of
# them handle formats unrelated to web images and are backed by third-party libraries. Left enabled,
# a crafted upload can reach one and read arbitrary files off the server.
#
# The content-type allowlists on avatars, logos, and message attachments are not a defense: libvips
# picks a loader from a file's actual bytes, not from the type the uploader declared.
#
# Autoload the transformer before blocking. Requiring it pulls in image_processing/vips, which sets
# its own policy as it loads, so touching it here makes the block below the last word no matter when
# Active Storage would otherwise have autoloaded it.
ActiveStorage::Transformers::Vips

unless Vips.respond_to?(:block_untrusted)
  raise "libvips #{Vips.version_string} cannot block untrusted operations. Upgrade to libvips >= 8.13."
end

Vips.block_untrusted(true)

# OpenSlide is fuzzed, but its embedded SQLite can segfault a forked worker.
Vips.block("VipsForeignLoadOpenslide", true)

# These formats now have no usable loader, so they can no longer be resized. Dropping them here
# makes Active Storage treat such attachments as non-variable rather than raising when something
# asks for a variant mid-request.
Rails.application.config.active_storage.variable_content_types -=
  %w[ image/bmp image/vnd.microsoft.icon image/vnd.adobe.photoshop ]
