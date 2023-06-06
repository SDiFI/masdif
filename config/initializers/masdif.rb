Rails.application.config.masdif = Rails.application.config_for('masdif')
if Rails.application.config.masdif[:tts][:enabled]
  Rails.application.config.after_initialize do
    TtsService.update
  end
end
