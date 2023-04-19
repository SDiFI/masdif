class ChatController < ApplicationController
  before_action :set_config

  def index
  end

  private

  def set_config
    @webchat_config = Rails.application.config.masdif[:chat_widget]
  end
end
