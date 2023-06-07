class AttachmentCleanupJob < ApplicationJob
  queue_as :default

  rescue_from ActiveJob::DeserializationError do |exception|
    # deleted message record
    Rails.logger.warn "================ ATTACHMENT CLEANUP ERROR: #{exception} ==============="
  end

  def perform(message_id, kwargs = {})
    Rails.logger.info "================ ATTACHMENT CLEANUP  #{message_id} ==============="
    message = Message.find_by(id: message_id)
    if message.nil?
      Rails.logger.error "================ ATTACHMENT CLEANUP ERROR: Message #{message_id} not found ==============="
    else
      # Cleans up given attachment
      case kwargs[:type]
      when :tts_audio
        message.tts_audio.purge
      else
          Rails.logger.warn "================ ATTACHMENT CLEANUP ERROR: #{kwargs[:type]} ==============="
      end
    end
    Rails.logger.info '================ ATTACHMENT CLEANUP ==============='
  end
end
