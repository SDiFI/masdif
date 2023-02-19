# This service implements accessing a configurable TTS service.

require 'grammatek-tts'

class TtsService < ApplicationService
  attr_reader :text
  mattr_reader :audio_path
  # List of available voices with encoded locale info; this is queried from TTS service and updated
  SUPPORTED_VOICES = []

  def self.update
    prepare_asset_path
    @@tts = Grammatek::TTS::SpeechApi.new(Grammatek::TTS::ApiClient.new(tts_config))
    # get list of all voices
    begin
      tts_voices = @@tts&.voices_get
      SUPPORTED_VOICES.clear
      tts_voices&.each do |voice|
        next if voice.language_code.nil? || voice.voice_id.nil?
        SUPPORTED_VOICES << "#{voice.language_code}-#{voice.voice_id}"
      end
    rescue Grammatek::TTS::ApiError => e
      Rails.logger.error "Error when calling SpeechApi->voices_get: #{e}"
      @@tts = nil
      throw e
    end
    @@tts
  end

  # Check if TTS service is available
  # @return [Boolean] true if TTS service is available, false if TTS service is not available
  def self.check_health
    # use a new instance of the TTS service, so that we don't interfere with the main instance
    tts = Grammatek::TTS::SpeechApi.new(Grammatek::TTS::ApiClient.new(tts_config))
    rv = false
    begin
      tts_voices = tts&.voices_get
      rv = true unless (tts_voices.nil? or tts_voices.empty?)
    rescue Grammatek::TTS::ApiError => e
      # if we get a 429, we assume that the service is up, but we're rate limited
      if e.code != nil and e.code == 429
        Rails.logger.warn "Rate limit exceeded, assuming TTS service is healthy"
        rv = true
      else
        Rails.logger.error "Error when calling SpeechApi->voices_get: #{e}"
      end
    end
    rv
  end

  def initialize(text, language, voice = nil)
    @@tts ||= TtsService.update
    @text = text
    @type = 'text'
    @language = language || 'is-IS'
    if validate_voice(voice, language)
      @voice = voice
    else
      @voice = default_voice_for_language(@language)
    end
    Rails.logger.info "TTS: synthesizing for #{@language} #{@voice}"
  end

  # Return generated audio mp3 file for text parameter given in constructor
  def call
    throw Grammatek::TTS::ApiError("No TTS service") if @@tts.nil?
    begin
      tempfile = @@tts&.speech_post(synthesize_default_params)
      throw Grammatek::TTS::ApiError("No audio returned") if tempfile.nil?

      # we need a unique file name that also makes it hard to guess from outside, so that
      # nobody can accidentally access it, before it's been deleted
      file_stem = Digest::SHA1.hexdigest("#{@text}.#{@language}.#{@voice}.#{Time.now}")
      mp3_file = "#{file_stem}.mp3"
      audio_file = "#{@@audio_path}/#{mp3_file}"

      # move received audio file to its destination
      FileUtils.cp(tempfile.path, audio_file)
      tempfile.delete
    rescue Grammatek::TTS::ApiError => e
      Rails.logger.error "Error when calling SpeechApi->speech_post_with_http_info: #{e}"
      @@tts = nil
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

  # Returns default voice name for given language. We use the first voice
  # that matches the language code.
  # If no voice is found, we return the first voice in the list.
  # Throws an exception if no voices are available.
  #
  # @param language [String] language code (e.g. 'is-IS')
  # @return [String] voice name (e.g. 'Dora')
  def default_voice_for_language(language)
    throw Grammatek::TTS::ApiError("No available TTS voices") if SUPPORTED_VOICES.empty?
    SUPPORTED_VOICES.each do |voice|
      if voice.start_with?(language)
        return voice.split('-')[2]
      end
    end
    SUPPORTED_VOICES.first.split('-')[2]
  end

  private

  # default parameters for TTS API call Grammatek::TTS::SynthesizeSpeechRequest
  def synthesize_default_params
    opts = {
      engine: 'standard',
      language_code: 'is-IS',
      lexicon_names: [],
      output_format: 'mp3',
      sample_rate: '16000',
      text: @text,
      text_type: @type,
      voice_id: @voice
    }
    Rails.logger.debug "TTS service parameters: #{opts}"
    {
      synthesize_speech_request: Grammatek::TTS::SynthesizeSpeechRequest.new(opts),
      debug_return_type: 'File'
    }
  end

  def validate_voice(voice, language)
    return false if voice.nil?
    return true if SUPPORTED_VOICES.include?("#{language}-#{voice}")
    false
  end

  # Server configuration for TTS API
  # The configuration is read from config/tts.yml
  def self.tts_config
    config = Rails.application.config_for(:tts)
    Rails.logger.info "Using TTS config: #{config}"
    Grammatek::TTS::Configuration.new do |c|
      c.host = config[:tts_host] or raise "TTS host not configured"
      c.base_path = config[:tts_base_path] or raise "TTS base path not configured"
      c.scheme = config[:tts_host_scheme] or raise "TTS scheme not configured"
      c.server_index = nil
    end
  end

end
