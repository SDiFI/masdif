include SharedMessageDefs

ActiveAdmin.register Message do

  belongs_to :conversation, optional: true

  include DateScopes

  config.sort_order = 'created_at_desc'

  actions :all, :except => [:new, :create, :edit, :destroy]

  filter :text, as: :string, label: 'User text'
  filter :bot_answer, as: :string, label: 'Bot answer'
  filter :feedback, as: :check_boxes, collection: -> { %w[positive negative none] }
  filter :intent, as: :select, collection: -> { Message.intent_list }
  filter :asr_generated, as: :boolean, label: 'ASR used ?'
  filter :created_at
  filter :verbosity, as: :select, collection: {'User' => 'user', 'Internal' => 'internal'}, label: 'Message type'

  # Customize index view, use highlight_feedback() to highlight feedback column depending on its value
  index row_class: ->msg { highlight_feedback(msg) } do
    message_columns
  end

end
