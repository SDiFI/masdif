class AddMoreIndexesToMessages < ActiveRecord::Migration[7.0]
  def change
    add_index :messages, :feedback
    add_index :messages, :text
  end
end
