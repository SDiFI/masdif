class ChangeMessagesReplyTypeToJson < ActiveRecord::Migration[7.0]

  def up
    # this only works if the column is compatible with jsonb
    messages = Message.all
    messages.each do |message|
      # Some messages have a reply column with a string value, some have a json value, try to unify them before
      # changing the column type to jsonb
      # read the reply column as a string and parse it as json, in case of an exception, try to parse it as a string
      # and try to convert it to json again. Then save everything as JSON string
      begin
        JSON.parse(message.reply)
      rescue JSON::ParserError => e
        message.update(reply: message.reply.to_json)
      end
    end
    change_column :messages, :reply, :jsonb, using: 'reply::text::jsonb'
  end

  def down
    change_column :messages, :reply, :string, using: 'reply::text::jsonb'
  end
end
