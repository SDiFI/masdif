class AttachmentCleanupJob < ApplicationJob
  queue_as :default

  def perform(message)
    Rails.logger.info "================ ATTACHMENT CLEANUP  #{message.id} ==============="
    # Cleans up given attachment
    message.tts_audio.purge
    Rails.logger.info '================ ATTACHMENT CLEANUP ==============='
  end
end
