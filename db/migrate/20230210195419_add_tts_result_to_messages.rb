class AddTtsResultToMessages < ActiveRecord::Migration[7.0]
  def change
    add_column :messages, :tts_result, :string, :default => 'none'
  end
end
