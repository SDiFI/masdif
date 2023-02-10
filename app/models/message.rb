class Message < ApplicationRecord
  belongs_to :conversation
  # asr_audio can be uploaded from either POST request or via
  # gRPC call from the client to the ASR proxy. We need it only for
  # a short time and delete it after processing.
  has_one_attached :asr_audio

  # tts audio file as returned from the TTS service
  has_one_attached :tts_audio

  def self.default_tts_result
    'none'
  end

  # todo: the following entries need to be set:
  #   - message type, e.g. user, bot, event, etc.
  #   - flags for ASR, etc.
end
