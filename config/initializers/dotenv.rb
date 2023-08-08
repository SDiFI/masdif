# config/initializers/dotenv.rb

# .env is already loaded at this time by dotenv-rails gem
Dotenv.require_keys("TTS_HOST", "TTS_BASE_PATH", "TTS_HOST_SCHEME")
