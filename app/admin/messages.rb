ActiveAdmin.register Message do

  belongs_to :conversation, optional: true

  # See permitted parameters documentation:
  # https://github.com/activeadmin/activeadmin/blob/master/docs/2-resource-customization.md#setting-up-strong-parameters
  #
  # Uncomment all parameters which should be permitted for assignment
  #
  # permit_params :conversation_id, :text, :meta_data, :reply, :tts_result, :feedback
  #
  # or
  #
  # permit_params do
  #   permitted = [:conversation_id, :text, :meta_data, :reply, :tts_result, :feedback]
  #   permitted << :other if params[:action] == 'create' && current_user.admin?
  #   permitted
  # end

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

  # Customize index view
  index row_class: ->elem { highlight_feedback(elem) } do
    column 'User text' do |m|
      link_to m.text, admin_message_path(m, scope: params[:scope])
    end
    column 'Bot answer', :reply_text
    column 'User Feedback', :feedback, class: 'col-user_feedback'
    column 'Intent', :intent
    column 'Entities', :entities
    column 'Slots', :slots
    column 'Actions', :actions
    column 'Voice Audio' do |m|
      audio_urls = m.audio_urls
      if audio_urls.nil? || audio_urls.empty?
        'N/A'
      else
        audio_tag audio_urls, controls: true, preload: 'none'
      end
    end
  end

end

# Return the CSS row_class to highlight the feedback
#
# @param [Message] elem the message
# @return [String] the CSS class
def highlight_feedback(elem)
  if elem.feedback == 'positive'
    'highlight-positive'
  elsif elem.feedback == 'negative'
    'highlight-negative'
  else elem.feedback == 'none'
    'highlight-none'
  end
end
