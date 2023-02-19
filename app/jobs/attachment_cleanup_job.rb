class AttachmentCleanupJob < ApplicationJob
  queue_as :default

  rescue_from ActiveJob::DeserializationError do |exception|
    # deleted message record
    Rails.logger.warn "================ ATTACHMENT CLEANUP ERROR: #{exception} ==============="
  end

  def perform(message)
    Rails.logger.info "================ ATTACHMENT CLEANUP  #{message.id} ==============="
    # Cleans up given attachment
    message.tts_audio.purge
    Rails.logger.info '================ ATTACHMENT CLEANUP ==============='
  end
end
