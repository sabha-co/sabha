class ApplicationController < ActionController::Base
  include AllowBrowser, RackMiniProfilerAuthorization, Authentication, Authorization, SetCurrentRequest, SetPlatform, TrackedRoomVisit, VersionHeaders, FragmentCache, Sidebar
  include Turbo::Streams::Broadcasts, Turbo::Streams::StreamName

  private
    # Turbo Drive prefetches links on hover via `<meta name="turbo-prefetch">`.
    # Prefetch requests carry the `Sec-Purpose: prefetch` header so the server
    # can skip side-effects (e.g. advancing a "seen" watermark) that should
    # only happen on a real visit.
    def turbo_prefetch?
      request.headers["Sec-Purpose"] == "prefetch"
    end
end
