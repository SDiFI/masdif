require 'tts_service'

# Monkey patch the ActiveStorage::Blob::Analyzable module to avoid the ActiveStorage::Blob::Analyzable#analyze_later method
# that can result in FileNotFound errors when the file is not yet available on the file system.
module ActiveStorage::Blob::Analyzable
  def analyze_later
    analyze
  end
end

class ConversationsController < ActionController::API
  include FeedbackConcern
  include ConversationConcern

  before_action :transform_params
  before_action :set_conversation, only: %i[ show update destroy ]
  before_action :set_feedback, only: %i[ update ]

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
    return if @conversation.nil?

    render json: {conversation_id: @conversation.id, messages: @conversation.messages}
  end

  # POST /conversations
  # POST /conversations.json
  #
  # Creates a new conversation and returns the ID of the new conversation. So far, no parameters are required.
  def create
    @conversation = Conversation.new(status: 'new')
    if @conversation.save!
      # add a restart event to the conversation
      event = "restart"
      meta_data = RasaHttp::DEFAULT_METADATA
      restart_msg = @conversation.messages.create(text: "/#{event}", meta_data: meta_data, tts_result: 'none')
      rasa = RasaHttp.new(RASA_HTTP_SERVER, RASA_HTTP_PORT, RASA_HTTP_PATH, RASA_HTTP_TOKEN)
      rasa_response = rasa.add_event(@conversation.id.to_s, restart_msg.id, event, "", meta_data)
      Rails.logger.info("Rasa response: #{rasa_response}")
      if rasa_response.status == 200
        # TODO: save the latest_event_time, so that we don't have to fetch the tracker before every message,
        #       then we always update the event time after we receive a message from dialog system
        restart_msg.update!(reply: rasa_response.body.to_json)
        render json: {conversation_id: @conversation.id}
      else
        restart_msg.update!(reply: rasa_response.reason_phrase.to_json)
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
  #   "message_id": "SOME_UUID",    (only valid in combination with /feedback{"value": "some_value"})
  #   "metadata":
  #       {
  #        "asr_generated": "true",
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
  #   "message_id": "UUID_FOR_THE_MESSAGE",
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
    start_time = Time.now
    return if @conversation.nil? || @feedback_error

    logger.info '================ REQUEST MSG START =============='
    prepare_meta_data

    @message = @conversation.messages.create(text: conversation_params[:text], meta_data: @meta_data, tts_result: @tts_result)
    if @message.nil?
      render json: @message.errors, status: :unprocessable_entity
      return
    end

    unless should_forward?
      render json: empty_response_message(@language, @meta_data)
      return
    end

    message_text = get_message_text
    latest_event_time = Time.at(get_tracker['latest_event_time'])
    http_response = send_to_dialog_system(message_text)
    process_response(http_response, start_time, latest_event_time)

    @message.time_overall = Time.now - start_time
    @message.save
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
    return if @conversation.nil?

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

end
