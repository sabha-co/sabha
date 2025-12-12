class ApplicationController < ActionController::Base
  include AllowBrowser, RackMiniProfilerAuthorization, Authentication, Authorization, BlockBannedRequests, SetCurrentRequest, SetPlatform, TrackedRoomVisit, VersionHeaders, FragmentCache, Sidebar
  include Turbo::Streams::Broadcasts, Turbo::Streams::StreamName
  include ForcePasswordChange  # Must be after Authentication to access Current.user
end
