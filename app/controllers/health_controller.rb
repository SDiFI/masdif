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
    rv[:sidekiq] = check_sidekiq

    # evaluate the overall health of the service
    if rv.values.any? { |v| v == :DOWN }
      rv[:masdif] = :UNHEALTHY
      render json: rv, status: :service_unavailable
    else
      rv[:masdif] = :OK
      render json: rv
    end
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
  # @return :OK if the database is up and all migrations completed, :DOWN otherwise
  def check_db
    rv = :DOWN
    begin
      if defined?(ActiveRecord)
        if ActiveRecord::Migrator.current_version && ActiveRecord::Migration.check_pending!.nil?
          rv = :OK
        end
      end
    rescue ActiveRecord::NoDatabaseError => e
      Rails.logger.error("Database error: #{e}")
    rescue MigrationError => e
      Rails.logger.error("Database migration error: #{e}")
    rescue StandardError => e
      Rails.logger.error("Error: #{e}")
    end
    rv
  end

  # Checks if sidekiq is up
  #
  # @return :OK if Sidekiq is up, :DOWN otherwise
  def check_sidekiq
    rv = :DOWN
    if defined?(::Sidekiq)
      ::Sidekiq.redis do |r|
        res = r.ping
        if res == "PONG"
          rv = :OK
        else
          Rails.logger.error("Sidekiq.redis.ping returned #{res.inspect} instead of PONG")
        end
      end
    end
    rv
  end

end
