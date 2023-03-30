require 'tts_service'

# Monkey patch the ActiveStorage::Blob::Analyzable module to avoid the ActiveStorage::Blob::Analyzable#analyze_later method
# that can result in FileNotFound errors when the file is not yet available on the file system.
module ActiveStorage::Blob::Analyzable
  def analyze_later
    analyze
  end
end

class ConversationsController < ApplicationController
  skip_forgery_protection
  before_action :transform_params
  before_action :set_conversation, only: %i[ show update destroy ]

  # GET /conversations
  # GET /conversations.json
  #
  # Shows the list of conversations.
  #
  # @note This is a privileged operation and requires the user to be logged in.
  #       This can also return a large number of records, so it is recommended to use pagination.
  # @return an array of conversation objects
  def index
    @conversations = Conversation.all
    render json: @conversations
  end

  # GET /conversations/1
  # GET /conversations/1.json
  #
  # Returns the conversation history for a given conversation ID.
  def show
    render json: {conversation_id: @conversation.id, messages: @conversation.messages}
  end

  # POST /conversations
  # POST /conversations.json
  #
  # Creates a new conversation and returns the ID of the new conversation. So far, no parameters are required.
  def create
    @conversation = Conversation.new(status: 'new', feedback: 'none')
    if @conversation.save!
      # add a restart event to the conversation
      event = "restart"
      meta_data = RasaHttp::DEFAULT_METADATA
      restart_msg = @conversation.messages.create(text: "/#{event}", meta_data: meta_data, tts_result: 'none')
      rasa = RasaHttp.new(RASA_HTTP_SERVER, RASA_HTTP_PORT, RASA_HTTP_PATH, RASA_HTTP_TOKEN)
      rasa_response = rasa.add_event(@conversation.id.to_s, event, "", meta_data)
      Rails.logger.info("Rasa response: #{rasa_response}")
      if rasa_response.status == 200
        restart_msg.update!(reply: rasa_response.body)
        render json: {conversation_id: @conversation.id}
      else
        restart_msg.update!(reply: rasa_response.reason_phrase)
        render json: {error: 'Rasa server error'}, status: :internal_server_error
      end
    else
      render json: @conversation.errors, status: :unprocessable_entity
    end
  end

  # PATCH/PUT /conversations/1
  # PATCH/PUT /conversations/1.json
  #  Forwards the message to the Rasa server.
  #
  #  the request message has the following format:
  #  {
  #   "text": "message text"
  #   "metadata":
  #       {
  #        "language": "is-IS",
  #        "tts": "true",
  #        "voice_id": "Dora",
  #      }
  #  }
  #
  # response
  #
  # [{
  # 	"text": "blubber",
  # 	"data": {
  # 		"elements": null,
  # 		"quick_replies": null,
  # 		"buttons": null,
  # 		"attachment": [{
  # 			"type": "video",
  # 			"payload ": {
  # 				"src ": "https://example.com/video.mp4"
  # 			},
  # 		  "type": "image",
  # 			"payload ": {
  # 				"src ": "https://example.com/image.jpeg"
  # 			}
  # 		}]
  # 	}
  # }]
  #
  def update
    logger.info '================ REQUEST MSG START =============='
    if conversation_params[:metadata]
      meta_params = conversation_params[:metadata].to_json
    else
      meta_params = RasaHttp::DEFAULT_METADATA.to_json
    end
    meta_data = JSON.parse(meta_params) || {}
    # TODO: refactor this out into a separate method
    language = meta_data['language'] || 'is-IS'
    voice = meta_data['voice_id'] || nil
    # check if meta_data['tts'] is set, if not, set it to true, if it is set to false, then use it
    if meta_data['tts'].nil?
      meta_data['tts'] = true
    end
    use_tts = true?(meta_data['tts'])
    tts_result = use_tts ? Message.default_tts_result : 'disabled'
    @message = @conversation.messages.create(text: conversation_params[:text], meta_data: meta_data, tts_result: tts_result)
    if @message
      rasa = RasaHttp.new(RASA_HTTP_SERVER, RASA_HTTP_PORT, RASA_HTTP_PATH, RASA_HTTP_TOKEN)
      rasa_response = rasa.rest_msg(@conversation.id.to_s, conversation_params[:text].to_s, meta_data)
      # rasa_response is an array of hashes
      json_reply = rasa_response.body
      if rasa_response.status == 200
        @message.reply = rasa_response.body
        if rasa_response.body.size > 0 and use_tts
          # we combine all text responses into one string for latency reasons
          rasa_answer = rasa_response.body.map{|t| t['text']}.join(' ')
          rasa_answer ||= t(:no_service)
          call_tts(rasa_answer, language, voice)
          if @message.tts_audio.attached?
            # add url for download
            tts_audio_url = rails_storage_proxy_url(@message.tts_audio)
            json_reply[0].merge!('data' => { 'attachment' => [{ 'type' => 'audio', 'payload' => { 'src' => tts_audio_url } }]})
            @message.tts_result = 'success'
          else
            @message.tts_result = 'error'
          end
        end
        @message.save
        # provide meta data back to all responses
        json_reply.each do |reply|
          reply.merge!( metadata: meta_data.merge(language: language))
        end
        render json: json_reply
      else
        @message.update!(reply: rasa_response.reason_phrase)
        render json: {error: 'Rasa server error'}, status: :internal_server_error
      end
    else
      render json: @message.errors, status: :unprocessable_entity
    end
    logger.info '================ REQUEST MSG END =============='
  end

  # DELETE /conversations/1
  # DELETE /conversations/1.json
  # This deletes the conversation history for a given conversation ID.
  # TODO: This is a privileged operation and requires the user to be logged in.
  #
  # Note: It's not possible to completely remove the conversation tracker via the Rasa API. One can use
  # RasaHttp.replace_events to replace all existing events of a conversation, e.g. with an empty list. But the
  # conversation ID itself can not be deleted as Rasa does not provide an API for this. One could add a job
  # that periodically removes old conversations from the database, but this is not implemented yet.
  def destroy
    success = @conversation.destroy
    if success
      rasa = RasaHttp.new(RASA_HTTP_SERVER, RASA_HTTP_PORT, RASA_HTTP_PATH, RASA_HTTP_TOKEN)
      rv = rasa.replace_events(@conversation.id.to_s, [])
      if rv.status == 200 and rv.body&.has_key?('events') and rv.body['events'] == []
        rv_status = :success
      else
        rv_status = :unprocessable_entity
      end
      render json: rv_status
    else
      render json: @message.errors, status: :unprocessable_entity
    end
  end

  private

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
        config = Rails.application.config_for(:tts)
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
      @conversation = Conversation.find(conversation_params[:id])
    end

    # Only allow a list of trusted parameters through.
  def conversation_params
      params.permit(:id, :language, :voice, :text, :conversation=> [], :metadata => [:voice_id, :language, :tts])
  end

  # Check if given object is true. This will do the following:
  # - if the object is a boolean, return the boolean value
  # - if the object is a string, return true if the string is "true" (case insensitive)
  # - otherwise return false
  def true?(obj)
    obj.to_s.downcase == "true"
  end
end
