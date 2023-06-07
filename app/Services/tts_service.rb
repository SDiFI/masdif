# This service implements accessing a configurable TTS service.

require 'grammatek-tts'

class TtsService < ApplicationService
  # Connection pool for TTS service
  TTS_POOL = ConnectionPool.new(size: 10, timeout: 5) do
    Grammatek::TTS::SpeechApi.new(Grammatek::TTS::ApiClient.new(tts_config))
  end

  class << self
    attr_accessor :supported_voices, :audio_path
  end

  attr_reader :text

  # List of available voices with encoded locale info; this is queried from TTS service and updated
  self.supported_voices = []

  def self.update
    prepare_asset_path
    # get list of all voices
    begin
      self.supported_voices.clear
      TTS_POOL.with do |tts|
        tts.voices_get&.each do |voice|
        next if voice.language_code.nil? || voice.voice_id.nil?
          self.supported_voices << "#{voice.language_code}-#{voice.voice_id}"
        end
      end
      config = Rails.application.config.masdif[:tts]
      unless validate_voice(config[:default_voice], config[:language])
        Rails.logger.warn("TTS configuration error: validation of configuration not compatible with service")
      end
    rescue Grammatek::TTS::ApiError => e
      Rails.logger.error "Error when calling SpeechApi->voices_get: #{e}"
      raise e
    end
  end

  # Check if TTS service is available
  # @return [Boolean] true if TTS service is available, false if TTS service is not available
  def self.check_health
    rv = false
    begin
      TTS_POOL.with do |tts|
        tts_voices = tts&.voices_get
        rv = true unless (tts_voices.nil? or tts_voices.empty?)
      end
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
    super()
    if self.class.supported_voices.nil? || self.class.supported_voices&.empty?
      Rails.logger.warn "TTS: supported_voices not yet loaded ?! Updating ..."
      TtsService.update
    end
    @text = text
    @type = 'text'
    @language = language || 'is-IS'
    if TtsService.validate_voice(voice, language)
      @voice = voice
    else
      @voice = default_voice_for_language(@language)
    end
    Rails.logger.info "TTS: synthesizing \'#{text}\' for #{@language} #{@voice}"
  end

  # Return generated audio mp3 file for text parameter given in constructor
  def call
    Rails.logger.info '================ TTS START =============='
    begin
      tempfile = post_tts(retries: 3)
      raise StandardError("No TTS audio file received") if tempfile.nil?
      audio_file = mk_dest_path
      FileUtils.cp(tempfile.path, audio_file)
      tempfile.delete
    rescue Grammatek::TTS::ApiError => e
      Rails.logger.error "Error when calling SpeechApi->speech_post_with_http_info: #{e}"
      raise e
    end
    Rails.logger.info '================ TTS END =============='
    audio_file
  end

  # If TTS is not working, we will not return anything to the user
  def self.no_service(exception)
    Rails.logger.error("TTS Exception: #{exception.inspect}")
    @tts = nil
  end

  # Prepare the path for downloaded TTS audio files.
  # Create it, if it doesn't exist and cleanup old files that might
  # already reside there.
  def self.prepare_asset_path
    self.audio_path = Rails.root.join('./app/assets/audios')
    FileUtils.mkdir_p self.audio_path
    # Remove old audio files from previous run
    old_audios = Dir.glob "#{self.audio_path}/*.mp3"
    FileUtils.rm_f(old_audios)
  end

  # Returns default voice name for given language. We use the first voice
  # that matches the language code.
  # If no voice is found, we return the first voice in the list.
  # raises an exception if no voices are available.
  #
  # @param language [String] language code (e.g. 'is-IS')
  # @return [String] voice name (e.g. 'Dora')
  def default_voice_for_language(language)
    config = Rails.application.config.masdif[:tts]
    return config[:default_voice] if TtsService.validate_voice(config[:default_voice], config[:language])

    raise Grammatek::TTS::ApiError("No available TTS voices") if self.class.supported_voices&.empty?
    self.class.supported_voices.each do |voice|
      if voice.start_with?(language)
        return voice.split('-')[2]
      end
    end
    self.class.supported_voices&.first.split('-')[2]
  end

  private

  # Generates the destination path for the synthesized audio file.
  # We generate a unique file name that makes it hard to guess from outside, so that
  # it cannot be accessed accidentally, before it's been deleted
  #
  # @return [String]  path to synthesized audio file
  def mk_dest_path
    file_stem = Digest::SHA1.hexdigest("#{@text}.#{@language}.#{@voice}.#{Time.now}")
    mp3_file = "#{file_stem}.mp3"
    "#{self.class.audio_path}/#{mp3_file}"
  end

  # Executes the TTS API call and returns the synthesized audio file
  #
  # @param retries [Integer] number of retries if rate limit is exceeded
  # @return [Tempfile, nil]  synthesized audio file
  def post_tts(retries: 3)
    success = false
    tempfile = nil
    status = nil
    retries.times do |i|
      pause = (i + 1) / 2.0
      TTS_POOL.with do |tts|
        tempfile, status, _headers = tts&.speech_post_with_http_info(synthesize_default_params)
      end
      case status
      when 200
        if tempfile.size > 0
          success = true
          break
        else
          Rails.logger.warn "TTS: received empty audio file ?! Trying again after #{pause} seconds ... (#{i + 1}/#{retries}"
          sleep(pause)
          next
        end
      when 429
        Rails.logger.warn "TTS: rate limit exceeded, trying again after #{pause} seconds ... (#{i + 1}/#{retries})"
        sleep(pause)
      else
        Rails.logger.error "TTS API problem, status #{status}"
        raise Grammatek::TTS::ApiError("TTS API problem: #{status}")
      end
    end
    raise Grammatek::TTS::ApiError("TTS API unsuccessful after #{retries} attempts.") unless success
    tempfile
  end

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

  def self.validate_voice(voice, language)
    return false if voice.nil?
    return true if self.supported_voices.include?("#{language}-#{voice}")
    false
  end

  # Server configuration for TTS API
  # The configuration is read from config/masdif.yml
  def self.tts_config
    config = Rails.application.config.masdif[:tts]
    Rails.logger.debug "Using TTS config: #{config}"
    Grammatek::TTS::Configuration.new do |c|
      c.host = config[:host] or raise "TTS host not configured"
      c.scheme = config[:host_scheme] or raise "TTS scheme not configured"
      c.base_path = config[:base_path] or raise "TTS base path not configured"
      c.server_index = nil
      c.debugging = config[:debugging] || false
      unless c.debugging
        c.logger = Logger.new(STDOUT)
        c.logger.level = Logger::WARN
      end
    end
  end

end
