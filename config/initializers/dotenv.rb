# config/initializers/dotenv.rb

Dotenv.parse(".env.deploy", ".env")
Dotenv.require_keys("TTS_HOST", "TTS_BASE_PATH", "TTS_HOST_SCHEME")
