# frozen_string_literal: true

class CorsController < ApplicationController
  def options
    render plain: ''
  end
end
