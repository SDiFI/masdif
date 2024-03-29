class Message < ApplicationRecord
  belongs_to :conversation
  # asr_audio can be uploaded from either POST request or via
  # gRPC call from the client to the ASR proxy. We need it only for
  # a short time and delete it after processing.
  has_one_attached :asr_audio

  # tts audio file(s) as returned from the TTS service
  has_many_attached :tts_audio

  after_save :update_conversation

  include TimeScopes

  scope :with_response, -> { where.not(reply: {}) }
  scope :with_intent, -> { where.not(nlu: {}) }
  scope :with_entities, -> { where.not(nlu: {}) }
  scope :exclude_internal, -> { where.not("text LIKE '/%'") }

  # For intent filtering, creates a list of all intents in the database
  scope :intent_list, -> { with_intent.pluck(:nlu).map do |nlu|
                              next if nlu.dig('intent', 'name').nil?
                              nlu['intent']['name']
                            end.uniq.sort }

  NOTHING = ''.freeze

  # to be able to use :intent as filter argument and matching the name of the filtered intent
  ransacker :intent do |parent|
    op = Arel::Nodes::InfixOperation.new('->>', Arel::Nodes.build_quoted("intent"), Arel::Nodes.build_quoted("name"))
    Arel::Nodes::InfixOperation.new('->', parent.table[:nlu], op)
  end

  ransacker :bot_answer do
    Arel.sql("(reply #>> '{0,text}')")
  end

  ransacker :asr_generated do |parent|
    Arel::Nodes::InfixOperation.new('->>', parent.table[:meta_data], Arel::Nodes.build_quoted('asr_generated'))
  end

  ransacker :verbosity do
    Arel.sql("(CASE WHEN text LIKE '/%' THEN 'internal' ELSE 'user' END)")
  end

  # Returns the bot reply as a String
  # @return [String] the bot reply
  def reply_text
    return nil if self.reply.nil?
    reply = self.reply
    if reply.is_a?(Array)
      reply.collect { |r| r['text'] }.join(". ")
    else
      reply['text'] || NOTHING
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
    return NOTHING if self.nlu.nil?
    nlu_result = self.nlu
    rv = ""
    intent = nlu_result['intent']
    if intent
      rv = "#{intent['name']}"
    end
    if rv.empty?
      rv = NOTHING
    end
    rv
  end

  # Return entities as a String, each separated by a comma
  # @return [String] the entities
  def entities
    return NOTHING if self.nlu.nil?
    nlu_result = self.nlu
    rv = ''
    if nlu_result['entities']&.any?
      nlu_result['entities'].each do |entity|
        rv += "#{entity['value']} (#{entity['entity']}), "
      end
    end
    if rv.empty?
      rv = NOTHING
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
    empty = [NOTHING]
    return empty if self.events.nil?
    rv = self.events.select { |e| e['event'] == 'slot' }.map do |slot|
      next if slot['name'].nil? || slot['name'] == 'session_started_metadata' || slot['value'].nil?
      "#{slot['value']} (#{slot['name']})"
    end.uniq
    rv.empty? ? empty : rv
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
          # sometimes the client sends the value with leading and trailing single quotes, remove them
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
    scope = verify_scope(scope)
    messages = self.send(scope.to_sym)

    intents_count = Hash.new(0)
    entities_count = Hash.new(0)
    actions_count = Hash.new(0)
    tts_count = 0
    asr_count = 0

    i_cnt = 0
    e_cnt = 0
    a_cnt = 0
    messages.pluck(:nlu, :events, :tts_result, :meta_data).each do |nlu, event, tts_result, meta_data|
      if meta_data
        asr_count += 1 if meta_data['asr_generated'] == true
      end
      if tts_result
        tts_count += 1 if tts_result == 'success'
      end
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
      tts_count: tts_count,
      asr_count: asr_count,
      intents_percentage: intents_count.transform_values { |v| (v.to_f / i_cnt * 100).round(2) }.map { |intent, count| { name: intent, data: count } },
      entities_percentage: entities_count.transform_values { |v| (v.to_f / e_cnt * 100).round(2) }.map { |entity, count| { name: entity, data: count } },
      actions_percentage: actions_count.transform_values { |v| (v.to_f / a_cnt * 100).round(2) }.map { |action, count| { name: action, data: count } }
    }
  end

  # Counts the number of messages that have been voted on via user feedback and returns the count as a Hash
  #
  # @param scope [String] the scope to use for the query
  # @return [Hash] the count as a Hash with the feedback values as keys and the counts as values, as well as an 'overall' key
  def self.feedback_counts(scope = 'all')
    scope = verify_scope(scope)

    messages = self.send(scope.to_sym).exclude_internal

    # Get feedback counts
    feedback_counts = messages.group(:feedback).count

    # Add overall count to the hash
    feedback_counts['overall'] = messages.count

    # Return the hash
    feedback_counts
  end

  # Returns the feedback counts for a specific conversation as a Hash
  #
  # @param conversation_id [String] the conversation id
  # @return [Hash] the count as a Hash with the feedback values as keys and the counts as values, as well as an 'overall' key
  def self.feedback_of_conversation(conversation_id)
    messages = self.where(conversation_id: conversation_id).exclude_internal

    # Get feedback counts
    feedback_counts = messages.group(:feedback).count

    # Add overall count to the hash
    feedback_counts['overall'] = messages.count

    # Return the hash
    feedback_counts
  end

  # Groups the messages by feedback value and returns the counts as an Array of Hashes
  # grouped by the specified period compatible with the groupdate gem
  #
  # @param scope [String] the scope to use for the query
  # @param period [String] the period to group by
  # @return [Array of Hashes] the counts as an Array of Hashes with the feedback values as keys and the counts as values
  def self.feedback_date_series(scope = 'all', period = 'day')
    scope = verify_scope(scope)

    # Translate period argument to groupdate function
    period = case period
             when 'hour', 'day', 'month', 'year'
               period.to_sym
             else
               raise ArgumentError, "Invalid period argument: #{period}"
             end

    messages = self.send(scope.to_sym).exclude_internal

    # Initialize an empty hash with mandatory feedback types, 'none' is not included
    feedback_types = %w[negative positive]
    series_data = feedback_types.map { |feedback| [feedback, {}] }.to_h
    # Get feedback counts grouped by the specified period
    messages.group(:feedback).group_by_period(period, :created_at, format: "%a, %d %b %Y").count.each do |(feedback, date), count|
      series_data[feedback][date] = count if feedback_types.include?(feedback)
    end

    # Collect all unique dates
    all_dates = series_data.values.flat_map(&:keys).uniq

    # Make sure every feedback type has a data point for every date
    series_data.each do |feedback, data|
      all_dates.each do |date|
        data[date] ||= 0
      end
    end

    # Convert series_data hash into an array of hashes
    series_data.map do |feedback, data|
      {name: feedback, data: data}
    end
  end

  private

  # Update the conversation's last_message_updated_at attribute
  def update_conversation
    conversation.update(last_message_updated_at: self.updated_at)
  end

  def self.verify_scope(scope)
    allowed_scopes = [:today, :this_week, :this_month, :last_30_days, :this_year, :all]
    scope = :all unless allowed_scopes.include?(scope.to_sym)
    scope
  end

end
