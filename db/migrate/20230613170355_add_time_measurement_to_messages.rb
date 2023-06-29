class AddTimeMeasurementToMessages < ActiveRecord::Migration[7.0]
  def change
    add_column :messages, :time_dialog, :float
    add_column :messages, :time_tts, :float
    add_column :messages, :time_overall, :float
  end
end
