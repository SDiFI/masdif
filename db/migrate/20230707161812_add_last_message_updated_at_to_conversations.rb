class AddLastMessageUpdatedAtToConversations < ActiveRecord::Migration[7.0]
  def up
    add_column :conversations, :last_message_updated_at, :datetime
    Conversation.reset_column_information
    Conversation.find_each do |conversation|
      last_message_update = conversation.messages.order(updated_at: :desc).first&.updated_at
      conversation.update_column(:last_message_updated_at, last_message_update)
    end
  end

  def down
    remove_column :conversations, :last_message_updated_at
  end
end
