class VersionController < ApplicationController
  include VersionHelper

  def show
    render plain: app_version
  end
end
