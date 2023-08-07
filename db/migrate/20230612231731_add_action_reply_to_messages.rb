class AddActionReplyToMessages < ActiveRecord::Migration[7.0]
  def up
    add_column :messages, :action_reply, :jsonb
    # extract the action_reply from the reply attribute for the key value
    # the reply attribute is a jsonb column and contains either an array of hashes or a simple hash. If it is an
    # array of hashes, then the action_reply needs to be searched by the key value 'custom' and the value of that
    # key is the action_reply. If the reply attribute is a simple hash, then the action_reply isn't nested and
    # can be extracted directly. After the action_reply is extracted, it is removed from the reply attribute.

    Message.reset_column_information

    Message.all.each do |message|
      reply = message.reply
      if reply&.is_a?(Array)
        indices_to_delete = []
        reply.each_with_index do |m, index|
          if m.has_key?('custom')
            val = JSON.parse(m['custom'], symbolize_names: true)
            transformed_val = val.deep_transform_keys { |key| key.to_s.underscore }
            message.update_column(:action_reply, transformed_val)
            # record the index to delete later
            indices_to_delete << index
          end
        end

        # remove the custom reply from the reply attribute
        indices_to_delete.reverse_each { |index| reply.delete_at(index) }
        message.update_column(:reply, reply)
      elsif reply.is_a?(Hash) && reply.has_key?('custom')
        val = JSON.parse(m['custom'], symbolize_names: true)
        transformed_val = val.deep_transform_keys { |key| key.to_s.underscore }
        message.update_column(:action_reply, transformed_val)
        # remove the custom reply from the reply attribute
        reply.delete('custom')
        message.update_column(:reply, reply)
      end
    end
  end

  def down
    Message.all.each do |message|
      action_reply = message.action_reply
      reply = message.reply

      if action_reply.present?
        if reply.is_a?(Array)
          reply << { 'custom' => action_reply.to_json }
          message.update_column(:reply, reply)
        elsif reply.is_a?(Hash) || reply.nil?
          reply = {} if reply.nil?
          reply['custom'] = action_reply.to_json
          message.update_column(:reply, reply)
        end
      end
    end

    remove_column :messages, :action_reply
  end
end

