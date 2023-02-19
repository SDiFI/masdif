# frozen_string_literal: true

class HealthController < ApplicationController

  # GET /health
  # GET /health.json
  #
  # Shows the health of the Masdif service and its dependencies
  #
  # @return a JSON object with the health of the service and its dependencies
  def index
    rv = {}
    rv[:database] = check_db
    rv[:dialog_system] = check_dialog_system
    # @todo: for tts, we need to implement throttling, so that we don't get rate limited
    rv[:tts] = TtsService.check_health ? :OK : :DOWN

    # evaluate the overall health of the service
    if rv.values.any? { |v| v == :DOWN }
      rv[:masdif] = :UNHEALTHY
    else
      rv[:masdif] = :OK
    end
    render json: rv
  end

  private

  # Checks if the dialog system is up
  #
  # @return :OK if the dialog system is up, :DOWN otherwise
  def check_dialog_system
    begin
      rasa = RasaHttp.new(RASA_HTTP_SERVER, RASA_HTTP_PORT, RASA_HTTP_PATH, RASA_HTTP_TOKEN)
      rasa_response = rasa.get_health
      if rasa_response.status == 200
        rv = :OK
      else
        rv = :DOWN
      end
    rescue StandardError => e
      e.backtrace&.each { |line| Rails.logger.error(line) }
      Rails.logger.error("Rasa error: #{e}")
      rv = :DOWN
    end
    rv
  end

  # Checks if the database is up
  #
  # @return :OK if the database is up, :DOWN otherwise
  def check_db
    begin
      conversation = Conversation.first
      if conversation != nil
        rv = :OK
      else
        rv = :DOWN
      end
    rescue ActiveRecord::NoDatabaseError => e
      Rails.logger.error("Database error: #{e}")
      rv = :DOWN
    end
    rv
  end

end
