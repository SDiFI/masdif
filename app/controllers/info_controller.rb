class InfoController < ApplicationController
  before_action :transform_params
  before_action :set_conversation, only: %i[ index ]
  before_action :set_config, only: %i[ index ]

  # GET /info
  # GET /info.json
  # Returns information about the dialog system like the motd (messages of the day) and all supported languages.
  # Request parameters:
  # - id: the conversation ID
  # - language: language of the conversation, if no language string is given, use the default language of
  #             the dialog system. This influences the language of the motd. If the given language is not
  #             supported, an HTTP error status code NOT_FOUND is returned.
  # Example return value:
  # {
  # 	"motd": [{
  #     "Góðan dag. Ég get svarað spurningum um Andabæ"
  #    }, {
  #     "Alls ekki láta mig fá persónuupplýsingar eins og nafn eða kennitölu."
  #   }],
  # 	"supported_languages": [{
  # 		"lang": "is-IS",
  # 		"explanation": "ég tala Íslensku"
  # 	}, {
  # 		"lang": "en-US",
  # 		"explanation": "English spoken here !"
  # 	}]
  # }
  def index
    return if @conversation.nil?
    return unless @config_loaded_successfully
    Rails.logger.debug("InfoController#index")

    language = params[:language] || @default_language
    unless @supported_languages.map { |l| l[:lang] }.include?(language)
      render json: { error: 'Unsupported language' }, status: :not_found
      return
    end
    rv = { 'supported_languages' => @supported_languages }

    # Use default MOTD if rasa_motd doesn't retrieve one
    rv['motd'] = rasa_motd(language) || @motd_config[:default][@default_language.to_sym]
    render json: rv, status: :ok
  end

  private

  # Retrieve MOTD from Rasa. Return an array of strings or nil if no MOTD was found.
  def rasa_motd(language)
    Rails.logger.info("Request MOTD for language #{language} ...")
    rasa = RasaHttp.new(RASA_HTTP_SERVER, RASA_HTTP_PORT, RASA_HTTP_PATH, RASA_HTTP_TOKEN)
    rasa_response = rasa.trigger_intent(@conversation.id, @motd_config[:rasa_intent], { language: language })

    unless rasa_response.status == 200
      Rails.logger.warn("Rasa: MOTD intent not recognized !")
      return nil
    end

    intent_messages = rasa_response.body.dig('messages')
    return Rails.logger.warn("Rasa: MOTD intent returned no results ?!") unless intent_messages&.size > 0

    intent_text = intent_messages[0].dig('text')
    return unless intent_text.is_a?(String)

    motd_h = JSON.parse(intent_text)
    motd = motd_h&.dig('motd', 'motd')
    if motd.nil?
      Rails.logger.warn("Rasa: MOTD intent returned no motd at expected location: #{pp intent_messages}")
    end
    if motd_h&.dig('motd', 'language') != language
      Rails.logger.warn("Rasa: MOTD intent returned motd for wrong language: #{pp intent_messages}")
      motd = nil
    end
    motd
  end

  # Sets configuration variables and tests for errors.
  def set_config
    @motd_config = Rails.application.config.masdif[:motd]
    @rasa_intent = @motd_config&.dig(:rasa_intent)
    @languages_config = Rails.application.config.masdif[:languages]
    @supported_languages = @languages_config&.dig(:supported)
    @default_language = @languages_config&.dig(:default)
    Rails.logger.error "No MOTD defined !" if @motd_config.nil?
    Rails.logger.error "No MOTD intent defined !" if @rasa_intent.nil?
    Rails.logger.error "No languages config defined !" if @languages_config.nil?
    Rails.logger.error "No supported languages defined !" if @supported_languages.nil?
    Rails.logger.error "No default language defined !" if @default_language.nil?

    @config_loaded_successfully = false
    if @motd_config.nil? || @rasa_intent.nil? || @languages_config.nil? || @default_language.nil? ||
      @supported_languages.nil?
      render json: {error: 'Internal server configuration error'}, status: :internal_server_error
    else
      @config_loaded_successfully = true
    end
  end

  # Transform the request parameters to snake_case, to make them compatible with Rails models
  def transform_params
    request.parameters.deep_transform_keys!(&:underscore)
  end

  # Rasa needs a conversation id to trigger an intent.
  # Check if given conversation exists.
  def set_conversation
    @conversation = Conversation.find_by(id: info_params[:id])
    if @conversation.nil?
      render json: {error: 'Conversation not found'}, status: :not_found
    end
  end

  # Only allow a list of trusted parameters.
  def info_params
    params.permit(:id, :language)
  end
end
