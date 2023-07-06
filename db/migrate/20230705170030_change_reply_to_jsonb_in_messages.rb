class ChangeReplyToJsonbInMessages < ActiveRecord::Migration[7.0]
  def up
    Message.transaction do
      Message.find_each do |message|
        begin
          if message.reply.present?
            json_string = message.reply.gsub('\\"', '"').gsub('\\\\', '\\')
            message.update_column(:reply, JSON.parse(json_string))
          end
        rescue JSON::ParserError => e
          Rails.logger.error("Error parsing JSON for Message ID #{message.id}: #{e.message}")
          message.update_column(:reply, {})
        end
        # Update all jsonb columns to have a default value of {}
        message.update_column(:meta_data, {}) if message.meta_data.nil?
        message.update_column(:reply, {}) if message.reply.nil?
        message.update_column(:nlu, {}) if message.nlu.nil?
        message.update_column(:events, {}) if message.events.nil?
        message.update_column(:action_reply, {}) if message.action_reply.nil?
      end
    end
  end

  def down
    Message.transaction do
      Message.find_each do |message|
        if message.reply.present?
          json_string = message.reply.to_json.gsub('"', '\\"').gsub('\\', '\\\\')
          message.update_column(:reply, json_string)
        end
      end
    end
  end
end
