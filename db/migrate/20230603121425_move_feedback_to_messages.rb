class MoveFeedbackToMessages < ActiveRecord::Migration[7.0]
  def change
    # move the feedback column from conversations to messages, existing feedback values are dropped, because
    # we haven't used them yet
    add_column :messages, :feedback, :string, :default => 'none'
    remove_column :conversations, :feedback
  end
end
