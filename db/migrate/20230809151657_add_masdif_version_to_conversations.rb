class AddMasdifVersionToConversations < ActiveRecord::Migration[7.0]
  include VersionHelper
  def change
    last_version = 'v0.3.4'
    add_column :conversations, :masdif_version, :string, null: false, default: last_version
    add_index :conversations, :masdif_version
  end
end
