module Api
  module V1
    class BaseController < ApplicationController
      # A user or guest token on every call; the few actions that must work without one skip it.
      before_action :require_api_token!
    end
  end
end
