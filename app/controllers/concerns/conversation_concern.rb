# frozen_string_literal: true

module ConversationConcern
  extend ActiveSupport::Concern

  private

  # Prepares the meta data for the conversation. If no meta data is provided, the default meta data is used.
  #
  # @return [void]
  def prepare_meta_data
    meta_params = conversation_params[:metadata] ? conversation_params[:metadata].to_json : RasaHttp::DEFAULT_METADATA.to_json
    @meta_data = JSON.parse(meta_params) || {}

    @language = @meta_data['language'] || 'is-IS'
    @voice = @meta_data['voice_id'] || nil
    @meta_data['tts'] = true if @meta_data['tts'].nil?
    @use_tts = true?(@meta_data['tts'])
    @tts_result = @use_tts ? Message.default_tts_result : 'disabled'
  end

  # Determines the message text to be forwarded to the dialog system.
  # If the message is a feedback message, the text from the feedback is used.
  # Otherwise the text from the request parameters [:text] is used.
  #
  # @return [String] the message text to be forwarded to the dialog system
  def get_message_text
    if @feedback
      @feedback[:text]
    else
      conversation_params[:text].to_s
    end
  end

  # Determines if the message should be forwarded to the dialog system.
  #
  # @return [Boolean] true if the message should be forwarded to the dialog system, false otherwise
  def should_forward?
    @feedback.nil? || @feedback[:do_forward]
  end

  # Sends the message to the dialog system.
  #
  # @param message_text [String] the message text to be forwarded to the dialog system
  # @return [Faraday::Response] the response from the dialog system
  def send_to_dialog_system(message_text)
    rasa = RasaHttp.new(RASA_HTTP_SERVER, RASA_HTTP_PORT, RASA_HTTP_PATH, RASA_HTTP_TOKEN)
    rasa.rest_msg(@conversation.id.to_s, message_text, @meta_data)
  end

  # Processes the response from the dialog system.
  #
  # If the response is successful, the response is processed and the message is updated with the response.
  # If the response is not successful, the message is updated with the error message.
  #
  # @param http_response [Faraday::Response]  response from the dialog system, already parsed from json
  # @return [void]
  def process_response(http_response)
    if http_response.status == 200
      render json: process_successful_response(http_response.body)
    else
      @message.update!(reply: http_response.reason_phrase)
      render json: {error: 'Dialog system error'}, status: :internal_server_error
    end
  end

  # Processes the response from the dialog system if the response is successful.
  # If the response is successful, the response is processed and the message is updated with the response.
  # If the response is not successful, the message is updated with the error message.
  # If the response is empty, an empty response message is returned.
  #
  # @param responses [Array, nil] response from the dialog system, already parsed from json
  # @return [String] the json reply
  def process_successful_response(responses)
    if responses&.size > 0
      process_tts(responses) if @use_tts
      append_metadata_and_message_id(responses)
    else
      responses = empty_response_message(@language, @meta_data)
    end

    begin
      json_reply = responses.to_json
    rescue StandardError => e
      Rails.logger.error("Error converting response to json: #{e.message}")
      json_reply = empty_response_message(@language, @meta_data).to_json
    end

    @message.reply = json_reply
    json_reply
  end

  # Processes TTS for the response from the dialog system.
  # @param [Array, nil] responses  response from the dialog system, already parsed from json
  # @return [void]
  def process_tts(responses)
    return if responses.nil?
    answer = responses&.map {|t| t['text']}&.join(' ')
    answer ||= t(:no_service)
    call_tts(answer, @language, @voice)

    if @message.tts_audio.attached?
      attach_tts_audio_url(responses[0])
      @message.tts_result = 'success'
    else
      @message.tts_result = 'error'
    end
  end

  # Attaches the TTS audio url to the json reply
  #
  # @param [Hash] response the response hash from the dialog system
  # @return [void]
  def attach_tts_audio_url(response)
    tts_audio_url = rails_storage_proxy_url(@message.tts_audio)
    response.merge!('data' => { 'attachment' => [{ 'type' => 'audio', 'payload' => { 'src' => tts_audio_url } }]})
  end

  # Appends the meta data and message id to the json reply
  #
  # @param [Array, nil] response   response from the dialog system, already parsed from json
  # @return [void]
  def append_metadata_and_message_id(response)
    return if response.nil?
    response&.each do |reply|
      reply.merge!( metadata: @meta_data.merge(language: @language), message_id: @message.id.to_s)
    end
  end

  # Just a bare-bones response message that is returned if e.g. a client feedback is not forwarded
  # or if the dialog system does not return any response.
  #
  # @param language [String] the language of the conversation
  # @param meta_data [Hash] the meta data of the conversation
  # @return [Array] the feedback message
  def empty_response_message(language, meta_data)
    [
      {
        metadata: meta_data.merge(language: language),
        message_id: @message.id.to_s,
        recipient_id: @conversation.id.to_s
      }
    ]
  end

  # Call TTS service and attach audio response to the message
  # @param [String] tts_text text to be converted to audio
  # @param [String] language language of the text
  # @param [String] voice voice to be used for the audio
  def call_tts(tts_text, language, voice)
    Rails.logger.info '================ START TTS ==============='
    begin
      Rails.logger.debug("TTS input: #{tts_text}, #{language}")
      tts_audio_file = TtsService.call(tts_text, language, voice)
      @message.tts_audio.attach(io: File.open("#{TtsService.audio_path}/#{tts_audio_file}"),
                                filename: File.basename(tts_audio_file))
      @message.save!
      # expire audio files
      config = Rails.application.config.masdif[:tts]
      expiration_in_secs = config[:tts_attachment_timeout] || 60
      AttachmentCleanupJob.set(wait: expiration_in_secs.to_i).perform_later(@message)
    rescue StandardError => e
      TtsService.no_service(e)
    end
    Rails.logger.info '================ END TTS ================='
  end

  # Transform the request parameters to snake_case, to make them compatible with Rails models
  def transform_params
    request.parameters.deep_transform_keys!(&:underscore)
  end

  # Use callbacks to share common setup or constraints between actions.
  def set_conversation
    @conversation = Conversation.find_by(id: conversation_params[:id])
    if @conversation.nil?
      render json: {error: 'Conversation not found'}, status: :not_found
    end
  end

  # Only allow a list of trusted parameters through.
  def conversation_params
    params.permit(:id, :language, :voice, :text, :message_id, :conversation => {},
                  :metadata => [:asr_generated, :language, :tts, :voice_id])
  end

  # Check if given object is true. This will do the following:
  # - if the object is a boolean, return the boolean value
  # - if the object is a string, return true if the string is "true" (case insensitive)
  # - otherwise return false
  def true?(obj)
    obj.to_s.downcase == "true"
  end

end
