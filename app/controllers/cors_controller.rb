# frozen_string_literal: true

class CorsController < ActionController::API
  def options
    render plain: ''
  end
end
