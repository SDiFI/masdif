require 'tts_service'

class ConversationsController < ApplicationController
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
      restart_msg = @conversation.messages.create(text: "/#{event}", meta_data: meta_data)
      rasa = RasaHttp.new(RASA_HTTP_SERVER, RASA_HTTP_PATH, RASA_HTTP_TOKEN)
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
  #   "sender id": "unique id of the sender",
  #   "message": "message text"
  #   "metadata":
  #       {
  #        "language": "is",
  #        "timezone": "Iceland",
  #        "tts": "true"
  #      }
  #  }
  #
  # response
  #
  # {
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
  # }
  #
  def update
    logger.info '================ REQUEST MSG START =============='
    meta_params = conversation_params[:metadata] || RasaHttp::DEFAULT_METADATA.to_json
    meta_data = JSON.parse(meta_params)
    language = meta_data[:language] || 'is-IS'
    voice = meta_data[:voice] || nil
    use_tts = meta_data[:tts] || 'true'

    @message = @conversation.messages.create(text: conversation_params[:text], meta_data: meta_data)
    if @message
      rasa = RasaHttp.new(RASA_HTTP_SERVER, RASA_HTTP_PATH, RASA_HTTP_TOKEN)
      rasa_response = rasa.rest_msg(@conversation.id.to_s, conversation_params[:text].to_s, meta_data)
      if rasa_response.status == 200
        @message.update!(reply: rasa_response.body)
        if rasa_response.body.size > 0 and use_tts
          rasa_answer = rasa_response.body.map{|t| t['text']}.join(' ')
          rasa_answer ||= t(:no_service)
          audio_file = call_tts(rasa_answer, language, voice)

          # TODO: attach audio to response as link: implementation is not correct
          # rasa_response.body['attachment']&.push({type: 'audio', payload: {src: audio_file}})
          logger.info " ..... Would have attached audio file #{audio_file} to response .... "
          # TODO: mark TTS as successfully called in message record
        end
      else
        @message.update!(reply: rasa_response.reason_phrase)
        render json: {error: 'Rasa server error'}, status: :internal_server_error
      end

      render json: rasa_response.body
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
      rasa = RasaHttp.new(RASA_HTTP_SERVER, RASA_HTTP_PATH, RASA_HTTP_TOKEN)
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
    # TODO: we shouldn't attach the audio to the message, but to the response object
    def call_tts(tts_text, language, voice)
      Rails.logger.info '================ START TTS ==============='
      answer_audio_file = nil
      begin
        Rails.logger.debug("TTS input: #{tts_text}, #{language}")
        answer_audio_file = TtsService.call(tts_text, language, voice)
        # @message.audio_answer.attach(io: File.open("#{TTSService.audio_path}/#{answer_audio_file}"),
        #                              filename: File.basename(answer_audio_file))
      rescue StandardError => e
        TtsService.no_service(e)
      end
      Rails.logger.info '================ END TTS ================='
      answer_audio_file
    end

    # Use callbacks to share common setup or constraints between actions.
    def set_conversation
      @conversation = Conversation.find(conversation_params[:id])
    end

    # Only allow a list of trusted parameters through.
  def conversation_params
      params.permit(:id, :metadata, :language, :voice, :text)
  end
end
