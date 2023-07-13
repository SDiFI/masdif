class AddMoreTrackerFieldsToMessages < ActiveRecord::Migration[7.0]
  def change
    add_column :messages, :nlu, :jsonb
    add_column :messages, :events, :jsonb
  end
end
