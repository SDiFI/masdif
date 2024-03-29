class Conversation < ApplicationRecord
  has_many :messages, dependent: :destroy

  include TimeScopes
  include VersionHelper

  # Returns the message as a JSON object, but deletes the id field and replaces it with conversation_id
  #
  # @return [Hash] the message as a JSON object
  # @example
  #  {
  #  "conversation_id": 1,
  #  "status": "active",
  #  "feedback": "positive",
  #  "created_at": "2018-03-01T00:00:00.000Z",
  #  "updated_at": "2018-03-01T00:00:00.000Z"
  # }
  #
  def as_json(*args)
    super.tap do |hash|
      hash['conversation_id'] = hash.delete "id"
    end
  end

  # Returns all versions of Masdif that are in use by conversations
  # @return [Array<String>] the versions
  def masdif_versions
    Conversation.distinct.pluck(:masdif_version)
  end

end
