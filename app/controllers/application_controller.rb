class ApplicationController < ActionController::Base
  include AllowBrowser, RackMiniProfilerAuthorization, Authentication, Authorization, SetCurrentRequest, SetPlatform, TrackedRoomVisit, VersionHeaders, FragmentCache, Sidebar
  include Turbo::Streams::Broadcasts, Turbo::Streams::StreamName
end
