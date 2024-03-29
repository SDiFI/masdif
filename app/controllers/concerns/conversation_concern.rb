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

  # Fetches the tracker from the dialog system, that belongs to the current conversation.
  # Returns an empty hash if the request fails.
  # @return [Hash] the latest message from the dialog system
  def get_tracker
    rasa = RasaHttp.new(RASA_HTTP_SERVER, RASA_HTTP_PORT, RASA_HTTP_PATH, RASA_HTTP_TOKEN)
    tracker_response = rasa.get_tracker(@conversation.id.to_s)
    if tracker_response.status != 200
      Rails.logger.error "Error getting tracker: #{tracker_response.body}"
      return {}
    end
    tracker_response.body
  end

  # Filter events by timestamp
  #
  # @param data [Hash] the tracker data
  # @param timestamp [Time] the timestamp to filter by
  # @return [Array] the filtered events
  def filter_events_by_timestamp(data, timestamp)
    return [] unless data.is_a?(Hash) && data['events'].is_a?(Array)

    data['events'].select do |event|
      event_timestamp = event['timestamp']
      event_time = Time.at(event_timestamp)
      event_time > timestamp
    end
  end

  # Filter given keys from a hash or an array of hashes recursively
  # @param input [Hash, Array] the input to be filtered
  # @param keys_to_filter [Array] the keys to be filtered
  # @return [Hash, Array] the filtered input
  def filter_keys(input, keys_to_filter)
    # If the input is an array, process each element recursively
    if input.is_a?(Array)
      return input.map { |item| filter_keys(item, keys_to_filter) }
    end

    # Base case: return the input if it's not a Hash
    return input unless input.is_a?(Hash)

    # Recursively process the hash
    filtered_hash = {}
    input.each do |key, value|
      # Check if the key is in the array of keys to be filtered
      next if keys_to_filter.include?(key)

      # If it's not, check if the value is a Hash or an Array and process it recursively
      if value.is_a?(Hash) || value.is_a?(Array)
        filtered_hash[key] = filter_keys(value, keys_to_filter)
      else
        filtered_hash[key] = value
      end
    end

    filtered_hash
  end

  # Processes the tracker from the dialog system.
  # If the tracker is not empty, the latest message and events are extracted and saved to the message.
  # Also these are filtered to remove unnecessary data.
  #
  # @param message [Message] the message to be updated
  # @param time_started [Time] the time when the request was sent to the dialog system
  # @param start_timestamp [Time] the timestamp of the latest event in the tracker
  # @return [void]
  def process_tracker(message, time_started, start_timestamp)
    tracker = get_tracker
    if tracker
      latest_message = tracker['latest_message']
      message.nlu = filter_keys(latest_message, %w[metadata message_id])
      events = filter_events_by_timestamp(tracker, start_timestamp)
      message.events = filter_keys(events, %w[parse_data metadata custom message_id timestamp])
      message.time_dialog = Time.now - time_started
    end
  end

  # Processes the response from the dialog system.
  #
  # If the response is successful, the response is processed and the message is updated with the response.
  # If the response is not successful, the message is updated with the error message.
  #
  # @param http_response [Faraday::Response]  response from the dialog system, already parsed from json
  # @param time_started [Time] the time when the request was sent to the dialog system
  # @param latest_event_timestamp [Time] the timestamp of the latest event in the tracker
  # @return [void]
  def process_response(http_response, time_started, latest_event_timestamp)
    if http_response.status == 200
      process_tracker(@message, time_started, latest_event_timestamp)
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
    if responses&.size&.positive?
      start_time = Time.now
      process_tts(responses) if @use_tts
      @message.time_tts = Time.now - start_time
      process_custom_actions(responses)
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

    @message.reply = responses
    json_reply
  end

  # Process custom actions from the dialog system.
  # If a key value 'custom' is present inside the responses array, the value of that
  # key is an action reply containing JSON. Save the action reply to the message and
  # remove the custom element from the reply attribute.
  # @param [Array, nil] responses  response from the dialog system, already parsed from json
  # @return [void]
  def process_custom_actions(responses)
    indices_to_delete = []
    responses&.each_with_index do |m, index|
      if m.has_key?('custom')
        # we symbolize the keys for easier conversion from mixed case to snake case
        # but these keys are again converted to normal strings when saved to the database
        val = JSON.parse(m['custom'], symbolize_names: true)
        transformed_val = val.deep_transform_keys { |key| key.to_s.underscore }
        @message.update(action_reply: transformed_val)
        # record the index to delete later
        indices_to_delete << index
      end
    end

    # remove the custom reply from the reply attribute
    indices_to_delete.reverse_each { |index| responses&.delete_at(index) }
  end

  # Processes TTS for the response from the dialog system.
  # @param [Array, nil] responses  response from the dialog system, already parsed from json
  # @return [void]
  def process_tts(responses)
    return if responses.nil?
    answer = responses&.map {|t| t['text']}&.join(' ')
    answer ||= t(:no_service)
    blob = call_tts(answer, @language, @voice)
    if blob.nil?
      @message.tts_result = 'error'
    else
      attach_tts_audio_url(responses[0], rails_blob_path(blob))
      @message.tts_result = 'success'
    end
  end

  # Attaches the TTS audio url to the json reply
  #
  # @param [Hash] response the response hash from the dialog system
  # @param [String] url the url to the TTS audio
  # @return [void]
  def attach_tts_audio_url(response, url)
    response.merge!('data' => { 'attachment' => [{ 'type' => 'audio', 'payload' => { 'src' => url } }]})
  end

  # Appends the meta data and message id to the json reply
  #
  # @param [Array, nil] response   response from the dialog system, already parsed from json
  # @return [void]
  def append_metadata_and_message_id(response)
    return if response.nil?
    response&.each do |reply|
      reply.merge!( metadata: @meta_data.merge(language: @language),
                    message_id: @message.id.to_s,
                    recipient_id: @conversation.id.to_s)
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
        metadata: meta_data.merge(language: language, asr_generated: false, tts: false),
        message_id: @message.id.to_s,
        recipient_id: @conversation.id.to_s
      }
    ]
  end

  # Call TTS service and attach audio response to the message
  #
  # @param [String] tts_text text to be converted to audio
  # @param [String] language language of the text
  # @param [String] voice voice to be used for the audio
  # @return [ActiveStorage::Blob, nil] the tts audio attachment blob
  def call_tts(tts_text, language, voice)
    Rails.logger.info '================ START TTS ==============='
    audio_blob = nil
    begin
      Rails.logger.debug("TTS input: #{tts_text}, #{language}")
      tts_audio_file = TtsService.call(tts_text, language, voice)

      audio_blob = ActiveStorage::Blob.create_and_upload!(
        io: File.open("#{tts_audio_file}"),
        filename: File.basename(tts_audio_file),
        content_type: 'audio/mpeg',
        identify: false
      )
      @message.tts_audio.attach audio_blob
      @message.save!

      FileUtils.rm_f(tts_audio_file)
      add_cleanup_job(@message.id)
    rescue StandardError => e
      TtsService.no_service(e)
    end
    Rails.logger.info '================ END TTS ================='
    audio_blob
  end

  # Add cleanup job to delete audio file after configured time
  # @param [String] message_id id of the message
  # @return [void]
  def add_cleanup_job(message_id)
    config = Rails.application.config.masdif[:tts]
    expiration_in_secs = config[:attachment_timeout] || 60
    AttachmentCleanupJob.set(wait: expiration_in_secs.to_i).perform_later(message_id, type: :tts_audio)
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
