class Message < ApplicationRecord
  belongs_to :conversation
  # asr_audio can be uploaded from either POST request or via
  # gRPC call from the client to the ASR proxy. We need it only for
  # a short time and delete it after processing.
  has_one_attached :asr_audio

  # tts audio file(s) as returned from the TTS service
  has_many_attached :tts_audio

  include TimeScopes

  # Returns the bot reply as a String
  # @return [String] the bot reply
  def reply_text
    return nil if self.reply.nil?
    begin
      reply = JSON.parse(self.reply)
      if reply.is_a?(Array)
        reply.collect { |r| r['text'] }.join(". ")
      else
        reply['text']
      end
    rescue JSON::ParserError => e
      return self.reply
    rescue StandardError => e
      return self.reply
    end
  end


  # Returns the TTS result as an array of audio URLs
  # @return [Array] the TTS result audio URLs
  def audio_urls
    return nil if self.reply.nil?
    attachments = self.tts_audio.all
    if attachments.empty?
      []
    else
      attachments.each_with_object([]) do |attachment, urls|
        urls << Rails.application.routes.url_helpers.rails_blob_url(attachment, only_path: true)
      end
    end
  end

  # Return the NLU result as a String
  #
  # @return [String] the NLU result
  def intent
    return 'N/A' if self.nlu.nil?
    nlu_result = self.nlu
    rv = ""
    intent = nlu_result['intent']
    if intent
      rv = "#{intent['name']}"
    end
    if rv.empty?
      rv = 'N/A'
    end
    rv
  end

  # Return entities as a String, each separated by a comma
  # @return [String] the entities
  def entities
    return 'N/A' if self.nlu.nil?
    nlu_result = self.nlu
    rv = ''
    if nlu_result['entities']&.any?
      nlu_result['entities'].each do |entity|
        rv += "#{entity['value']} (#{entity['entity']}), "
      end
    end
    if rv.empty?
      rv = 'N/A'
    end
    rv.chomp(', ')
  end

  # Return actions as an array of Strings
  # @return [Array] the actions
  def actions
    return [] if self.events.nil?
    self.events.select { |e| e['event'] == 'action' }.map { |action| action['name'] }
  end

  # Return slots as an array of Strings
  # @return [Array] the slots
  def slots
    return [] if self.events.nil?
    self.events.select { |e| e['event'] == 'slot' }.map do |slot|
      next if slot['name'] == 'session_started_metadata'
      slot['value'] + ' ('+ slot['name'] + ')'
    end.uniq
  end

  def self.default_tts_result
    'none'
  end

  # Parse the text body for /feedback{"value": "some value"} and
  # return the value. If no feedback is found, return nil.
  # If the feedback is invalid, return 'invalid'.
  #
  # @param text [String] the text body of the message
  # @return [String, nil] the feedback value or nil
  def self.parse_feedback(text)
    if text&.starts_with?('/feedback')
      # we have a feedback request
      # everything behind /feedback is a JSON string
      begin
        feedback = JSON.parse(text.sub('/feedback', ''))
        if feedback['value'].nil?
          return 'invalid'
        else
          value = feedback['value']
          return value.delete_prefix("'").delete_suffix("'")
        end
      rescue JSON::ParserError => e
        return 'invalid'
      end
    else
      return nil
    end
  end

  # Count various statistics, i.e. intents, entities, actions for messages, optionally scoped
  # to a specific time period and return the counted buckets as a Hash
  #
  # @param scope [String] the scope to use for the query
  # @return [Hash] various counts as a Hash with the following keys:
  #                  :intents_count, :entities_count, :actions_count,
  #                  :intents_percentage, :entities_percentage, :actions_percentage
  #                and the following values:
  #                 Hash with the intent/entity/action name as value for key :name and the count as value for key :data
  def self.stats_counts(scope = 'all')
    # verify that the scope is valid
    allowed_scopes = [:today, :this_week, :this_month, :this_year, :all]
    scope = :all unless allowed_scopes.include?(scope.to_sym)

    messages = self.send(scope.to_sym)
    intents_count = Hash.new(0)
    entities_count = Hash.new(0)
    actions_count = Hash.new(0)

    i_cnt = 0
    e_cnt = 0
    a_cnt = 0
    messages.pluck(:nlu, :events).each do |nlu, event|
      if event
        event.each do |e|
          next unless e['event'] == 'action'
          actions_count[e['name']] += 1
          a_cnt += 1
        end
      end
      next if nlu.nil? || nlu.empty?
      intent_name = nlu['intent']['name']
      intents_count[intent_name] += 1
      i_cnt += 1

      nlu['entities'].each do |entity|
        entities_count[entity['value']] += 1
        e_cnt += 1
      end
    end

    # The format here is as the UI graph component expects it
    {
      intents_count: intents_count.map { |intent, count| { name: intent, data: count } },
      entities_count: entities_count.map { |entity, count| { name: entity, data: count } },
      actions_count: actions_count.map { |action, count| { name: action, data: count } },
      intents_percentage: intents_count.transform_values { |v| (v.to_f / i_cnt * 100).round(2) }.map { |intent, count| { name: intent, data: count } },
      entities_percentage: entities_count.transform_values { |v| (v.to_f / e_cnt * 100).round(2) }.map { |entity, count| { name: entity, data: count } },
      actions_percentage: actions_count.transform_values { |v| (v.to_f / a_cnt * 100).round(2) }.map { |action, count| { name: action, data: count } }
    }
  end

end
