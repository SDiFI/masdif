class CreateConversations < ActiveRecord::Migration[7.0]
  def change
    enable_extension 'pgcrypto'
    create_table :conversations, id: :uuid do |t|
      t.timestamps
      t.string :status
      t.string :feedback
    end

    create_table :messages do |t|
      t.belongs_to :conversation, index: true, type: :uuid, foreign_key: true
      t.timestamps
      t.string :text
      if Rails.env.development?
        t.json :meta_data
      else
        t.jsonb :meta_data
      end
      t.string :reply
    end
  end
end
