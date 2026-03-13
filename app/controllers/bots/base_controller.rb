class Bots::BaseController < ApplicationController
  skip_forgery_protection
  allow_bot_access
end
