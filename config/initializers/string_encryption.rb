require 'openssl'

keygen = OpenSSL::Cipher.new('aes-128-cbc').encrypt
Rails.configuration.string_enc_key = keygen.random_key

# Monkey patch String class to add encrypt and decrypt methods
class String
  def encrypt
    cipher = OpenSSL::Cipher::AES.new(128, :CBC).encrypt
    cipher.key = Rails.configuration.string_enc_key
    encrypted = cipher.update(self) + cipher.final
    Base64.urlsafe_encode64(encrypted)
  end

  def decrypt
    begin
      decoded = Base64.urlsafe_decode64(self)
      cipher = OpenSSL::Cipher::AES.new(128, :CBC).decrypt
      cipher.key = Rails.configuration.string_enc_key
      cipher.update(decoded) + cipher.final
    rescue => e
      self
    end
  end
end

