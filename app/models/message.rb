class Message < ApplicationRecord
  belongs_to :conversation
  # asr_audio can be uploaded from either POST request or via
  # gRPC call from the client to the ASR proxy. We need it only for
  # a short time and delete it after processing.
  has_one_attached :asr_audio

  # tts audio file(s) as returned from the TTS service
  has_many_attached :tts_audio

  def self.default_tts_result
    'none'
  end

  # Parse the text body for /feedback{"value": "some value"} and
  # return the value. If no feedback is found, return nil.
  # If the feedback is invalid, return 'invalid'.
  #
  # @param text [String] the text body of the message
  # @return [String, nil] the feedback value or nil
  def self.parse_feedback(text)
    if text&.starts_with?('/feedback')
      # we have a feedback request
      # everything behind /feedback is a JSON string
      begin
        feedback = JSON.parse(text.sub('/feedback', ''))
        if feedback['value'].nil?
          return 'invalid'
        else
          value = feedback['value']
          return value
        end
      rescue JSON::ParserError => e
        return 'invalid'
      end
    else
      return nil
    end
  end

end
