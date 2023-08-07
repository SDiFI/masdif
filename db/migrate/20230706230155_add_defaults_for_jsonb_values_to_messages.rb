class AddDefaultsForJsonbValuesToMessages < ActiveRecord::Migration[7.0]
  def up
    # Set default value and non-null constraint for each jsonb column
    change_column_default :messages, :meta_data, from: nil, to: {}
    change_column_null :messages, :meta_data, false

    change_column_default :messages, :reply, from: nil, to: {}
    change_column_null :messages, :reply, false

    change_column_default :messages, :action_reply, from: nil, to: {}
    change_column_null :messages, :action_reply, false

    change_column_default :messages, :nlu, from: nil, to: {}
    change_column_null :messages, :nlu, false

    change_column_default :messages, :events, from: nil, to: {}
    change_column_null :messages, :events, false
  end

  def down
    change_column_default :messages, :meta_data, from: {}, to: nil
    change_column_null :messages, :meta_data, true

    change_column_default :messages, :reply, from: {}, to: nil
    change_column_null :messages, :reply, true

    change_column_default :messages, :action_reply, from: {}, to: nil
    change_column_null :messages, :action_reply, true

    change_column_default :messages, :nlu, from: {}, to: nil
    change_column_null :messages, :nlu, true

    change_column_default :messages, :events, from: {}, to: nil
    change_column_null :messages, :events, true
  end
end
