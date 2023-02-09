# This service implements accessing a configurable TTS service.

require 'grammatek-tts'

class TtsService < ApplicationService
  attr_reader :text
  mattr_accessor :audio_path

  def self.update
    prepare_asset_path
    server_config = tts_config_grammatek_v0
    @@tts = Grammatek::TTS::SpeechApi.new(Grammatek::TTS::ApiClient.new(server_config))
  end

  def initialize(text, language, voice = nil)
    @@tts ||= nil
    @text = text
    @type = 'text'
    @voice = voice || voice_for_language(language)
    @language = language
    Rails.logger.info "TTS: synthesizing for #{@language} #{@voice}"
  end

  # Return generated audio file for text parameter given in constructor
  def call
    TtsService.update if @@tts.nil?
    # we need a unique file name that also makes it hard to guess from outside, so that
    # nobody can accidentally access it, before it's been deleted
    file_stem = "#{@text}.#{@language}.#{@voice}".encrypt
    mp3_file = "#{file_stem}.mp3"
    audio_file = "#{@@audio_path}/#{mp3_file}"
    # ToDo - check if file exists and is not too old (e.g. N days - configurable) and return it instead of generating
    #        it again (this is a performance optimization)
    #      - cleanup old files (e.g. after N days - configurable)
    params = {
      engine: 'standard',
      language_code: 'is-IS',
      lexicon_names: [],
      output_format: 'mp3',
      #sample_rate: '24000',  # Not supported yet
      sample_rate: '16000',
      text: @text,
      text_type: @type,
      voice_id: @voice
    }

    Rails.logger.debug "TTS: #{params}"
    opts = {
      synthesize_speech_request: Grammatek::TTS::SynthesizeSpeechRequest.new(params),
      debug_return_type: 'File'
    }

    begin
      tempfile = @@tts&.speech_post(opts)
      return "" if tempfile.nil?

      # move the received audio file to its destination
      FileUtils.cp(tempfile.path, audio_file)
      tempfile.delete
    rescue Grammatek::TTS::ApiError => e
      Rails.logger.error "Error when calling SpeechApi->speech_post_with_http_info: #{e}"
      throw e
    end
    mp3_file
  end

  # If TTS is not working, we will not return anything to the user
  def self.no_service(exception)
    Rails.logger.error("TTS Exception: #{exception.inspect}")
    @@tts = nil
  end

  # Prepare the path for downloaded TTS audio files.
  # Create it, if it doesn't exist and cleanup old files that might
  # already reside there.
  def self.prepare_asset_path
    @@audio_path = Rails.root.join('./app/assets/audios')
    FileUtils.mkdir_p @@audio_path
    # Remove old audio files from previous run
    old_audios = Dir.glob "#{@@audio_path}/*.mp3"
    FileUtils.rm_f(old_audios)
  end

  # Returns supported voice name for given language.
  def voice_for_language(language)
    case language
    when 'is-IS'
      'Alfur'
      # TODO: make usage of the voice configurable, e.g. if we use different personas for the bot ..
    else
      'Karl'
    end
  end

  private

  # Server configuration for Grammatek TTS v0 API
  def self.tts_config_grammatek_v0
    Grammatek::TTS::Configuration.new do |c|
      c.host = 'api.grammatek.com'
      c.base_path = '/tts/v0'
      c.scheme = 'https'
      c.server_index = nil
    end
  end

  # Server configuration for Tíro TTS v0 API
  def self.tts_config_tiro_v0
    Grammatek::TTS::Configuration.new do |c|
      c.host = 'tts.tiro.is'
      c.base_path = '/v0'
      c.scheme = 'https'
      c.server_index = nil
    end
  end

end
