# frozen_string_literal: true

#  Implement a Rasa HTTP client according to the Rasa HTTP API at https://rasa.com/docs/rasa/api/http-api/

# We are currently opening a new connection for each request. This is not the most efficient way to do it, but it let's
# us parallelize incoming requests. If we want to optimize this, we can use a connection pool.

class RasaHttp
  DEFAULT_METADATA = { asr_generated: false, language: 'is-IS' }.freeze

  def initialize(host, port, base_path, token)
    if host.start_with?('http://') || host.start_with?('https://')
      @host = "#{host}:#{port}"
    else
      @host = "http://#{host}:#{port}"
    end

    @base_path = base_path
    @token = token
    Rails.logger.info "RasaHttp connection: #{@host}"
    @conn = Faraday.new(url: @host) do |conn|
      conn.request :json
      conn.request :authorization, :Token, @token
      conn.response :json
      conn.adapter Faraday.default_adapter
      conn.headers['Accept'] = 'application/json'
      conn.headers['Accept'] = 'application/yaml'
    end
  end

  # Builds a path for the Rasa HTTP API by prepending the base path
  #
  # @param [String] path the path to append to the base path
  # @return [String] the full path
  #
  # @example
  #  build_path('/status') # => '/api/v1/status'
  def build_path(path)
    "#{@base_path}/#{path}".gsub(/\/+/, '/')
  end

  # Health endpoint of Rasa Server
  # This URL can be used as an endpoint to run health checks against. When the server is running this will return 200.
  def get_health
    path = build_path('/')
    @conn.get(path)
  end

  # Status of the Rasa server
  # Information about the server and the currently loaded Rasa model.
  def get_status
    @conn.get(build_path('/status'), { token: @token })
  end

  # Version of Rasa
  # Returns the version of Rasa.
  def get_version
    @conn.get(build_path('/version'), { token: @token })
  end

  # Retrieve the loaded domain
  # Returns the domain specification the currently loaded model is using.
  def get_domain
    @conn.get(build_path('/domain'), { token: @token })
  end

  # Retrieve a conversations tracker
  # The tracker represents the state of the conversation. The state of the tracker is created by applying a sequence
  # of events, which modify the state. These events can optionally be included in the response.
  def get_tracker(conversation_id)
    @conn.get(build_path("/conversations/#{conversation_id}/tracker"), { token: @token })
  end

  # Retrieve an end-to-end story corresponding to a conversation
  # The story represents the whole conversation in end-to-end format. This can be posted to the '/test/stories' endpoint
  # and used as a test.
  def get_story(conversation_id)
    @conn.get(build_path("/conversations/#{conversation_id}/story"), { token: @token })
  end

  # Adds a message to a tracker. This doesn't trigger the prediction loop. It will log the message on the tracker and
  # return, no actions will be predicted or run. This is often used together with the predict endpoint.
  def add_message(conversation_id, message)
    @conn.post(build_path("/conversations/#{conversation_id}/messages"), { token: @token, message: message })
  end

  # Appends one or multiple new events to the tracker state of the conversation. Any existing events will be kept
  # and the new events will be appended, updating the existing state. If events are appended to a new conversation ID,
  # the tracker will be initialised with a new session.
  def add_event(conversation_id, event, text, metadata = DEFAULT_METADATA)
    @conn.post build_path("/conversations/#{conversation_id}/tracker/events") do |req|
      req.params[:token] = @token
      case event
      when 'user'
        req.body = JSON.generate(sender: conversation_id, event: event, text: text, metadata: metadata)
      when 'restart'
        # metadata must not be empty if set
        req.body = JSON.generate(sender: conversation_id, event: event, metadata: metadata)
      else
        Rails.logger.warn "Unknown event type #{event} given to RasaHttp#add_event"
        req.body = JSON.generate(sender: conversation_id, event: event, text: text, metadata: metadata)
      end
    end
  end

  # Replace a trackers events
  # Replaces all events of a tracker with the passed list of events. This endpoint should not be used to modify trackers
  # in a production setup, but rather for creating training data.
  def replace_events(conversation_id, events)
    @conn.put build_path("/conversations/#{conversation_id}/tracker/events") do |req|
      req.params[:token] = @token
      req.body = JSON.generate(events)
    end
  end

  # Predict the next action
  # Runs the conversations tracker through the model's policies to predict the scores of all actions present in
  # the model's domain. Actions are returned in the 'scores' array, sorted on their 'score' values.
  # The state of the tracker is not modified.
  def predict(conversation_id)
    @conn.post build_path("/conversations/#{conversation_id}/predict") do |req|
      req.params[:token] = @token
    end
  end

  # Sends a textual message to the bot.
  #
  # @param [String] sender_id The sender id
  # @param [String] msg The message
  # @return [String] The response. JSON encoded string containing an array with the following keys:
  #     `recipient_id`, `text`, `buttons`. The buttons are optional and only present if the bot
  #     response contained buttons. The buttons are an array of dictionaries with the following keys
  #     `title`, `payload`. The `payload` is the value that will be sent back to the bot if the user
  #     clicks on the button. The `title` is the text that will be displayed on the button. The `text`
  #     is the text that the bot will send back to the user. The `recipient_id` is the id of the user
  # that sent the message.
  # @example
  #  rasa_http.send_message('sender_1674484968', 'hver er bæjastjóri ?')
  #  =>
  #  [
  #         [0] {
  #             "recipient_id" => "sender_1674484968",
  #                     "text" => "Um hvað viltu tala, segirðu? Þú getur reynt að umorða spurninguna eða valið málaflokk.",
  #                  "buttons" => [
  #                 [ 0] {
  #                     "payload" => "/request_contact{\"subject\":\"Skipulagsmál\"}",
  #                       "title" => "Skipulagsmál"
  #                 },
  #                 [ 1] {
  #                     "payload" => "/request_contact{\"subject\":\"Garðamál\"}",
  #                       "title" => "Garðamál"
  #                 },
  #                 ...
  #                 },
  #                 [10] {
  #                     "payload" => "/request_contact{\"subject\":\"Dýraeftirlit\"}",
  #                       "title" => "Dýraeftirlit"
  #                 }
  #             ]
  #        }
  #   ]
  def rest_msg(sender_id, msg, metadata = DEFAULT_METADATA)
    @conn.post build_path("/webhooks/rest/webhook") do |req|
      req.params[:token] = @token
      req.body = JSON.generate(sender: sender_id, message: msg, metadata: metadata)
    end
  end

  def rest_delete(conversation_id)
    # delete conversation from tracker store
    @conn.delete build_path("/conversations/#{conversation_id}/tracker") do |req|
      req.params[:token] = @token
    end
  end

  # Evaluates given text on Rasa model and returns the evaluation results without modifying the tracker state.
  # This can be used to see how the model would respond to a given message without making it part of the conversation.
  #
  # An example of a request:
  # {
  #   "text": "Hello!",
  #   "message_id": "unique_id"
  # }
  #
  # An example of a response:
  # {
  #   "entities": [
  #     {
  #       "start": 0,
  #       "end": 0,
  #       "value": "string",
  #       "entity": "string",
  #       "confidence": 0
  #     }
  #   ],
  #   "intent": {
  #     "confidence": 0.6323,
  #     "name": "greet"
  #   },
  #   "intent_ranking": [
  #     {
  #       "confidence": 0.6323,
  #       "name": "greet"
  #     }
  #   ],
  #   "text": "Hello!"
  # }
  #
  # @param [String] text The text to evaluate
  # @param [String] msg_id The message id (optional - will be generated if not given)
  def model_parse(text, msg_id = nil)
    message_id = msg_id || SecureRandom.uuid
    @conn.post build_path("/model/parse") do |req|
      req.params[:token] = @token
      req.body = JSON.generate(text: text, message_id: message_id)
    end
  end

  # Triggers directly given intent without passing through NLU pipeline.
  # This can be used to directly trigger an action or to circumvent the NLU pipeline if the intent was
  # predicted otherwise.
  #
  # An example of a request:
  # {
  #   "name": "greet",
  #   "entities": {
  #     "temperature": "high"
  #   }
  # }
  # Example of a response:
  # {
  #   "tracker": { .. },
  #   "messages": [
  #     {
  #       "recipient_id": "string",
  #       "text": "string",
  #       "image": "string",
  #       "buttons": [
  #         {
  #           "title": "string",
  #           "payload": "string"
  #         }
  #       ],
  #       "attachment": [
  #         {
  #           "title": "string",
  #           "payload": "string"
  #         }
  #       ]
  #     }
  #   ]
  # }
  # @param [String] conversation_id The conversation id
  # @param [String] intent          The intent to trigger
  # @param [Hash]   entities        The entities for the intent
  #
  # @note: The state of the tracker is modified as if the intent was predicted by the NLU pipeline.
  def trigger_intent(conversation_id, intent, entities = {})
    @conn.post build_path("/conversations/#{conversation_id}/trigger_intent") do |req|
      req.params[:token] = @token
      req.body = JSON.generate(name: intent, entities: entities)
    end
  end

  def todo
    # POST /model/predict
    # PUT /model
    # POST /model/test/intents
    # POST /model/test/stories
    # POST /model/train
    # DELETE /model
    # POST /conversations/{conversation_id}/execute
  end
end
