include SharedMessageDefs

ActiveAdmin.register Conversation do

  include DateScopes

  config.sort_order = 'created_at_desc'

  actions :all, :except => [:new, :create, :edit]

  filter :messages_text_cont, as: :string, label: 'User text'
  filter :messages_bot_answer_cont, as: :string, label: 'Bot answer'
  filter :messages_feedback, as: :check_boxes, label: 'Feedback', collection: -> { %w[positive negative none] }
  filter :messages_intent_in, as: :select, collection: -> { Message.intent_list }, label: 'Intent'
  filter :messages_asr_generated_eq, as: :boolean, label: 'ASR used ?'
  filter :created_at
  filter :masdif_version, as: :string, label: 'Version'

  controller do
    def scoped_collection
      # we need to use distinct here, otherwise we get duplicate results for multiple messages in a conversation
      end_of_association_chain.distinct
    end
  end

  index do
    selectable_column
    column :messages do |conversation|
      message_texts = conversation.messages.exclude_internal.order(:created_at).map(&:text)
      excerpt_text = message_texts.join(" => ").truncate(100)
      link_to excerpt_text, admin_conversation_path(conversation)
    end
    column :feedback do |conversation|
      feedback_counts = Message.feedback_of_conversation(conversation.id)
      feedback_values = [feedback_counts['positive'] || 0, feedback_counts['negative'] || 0]
      colors = %w[#00FF00 #FF0000] # Green for positive, red for negative
      # Only create a chart if there are positive or negative feedbacks
      if feedback_values.sum > 0
        pie_chart(feedback_values,
                  legend: false,
                  colors: colors,
                  width: "80px",
                  height: "80px",
                  chart: { animations: { enabled: false } })
      else
        'N/A' # Display 'N/A' if there are no feedbacks or all feedbacks are 'none'
      end
    end
    column :created_at
    column "Updated At", :last_message_updated_at
    column "Masdif Version", :masdif_version

    if authorized? :manage, Conversation
      actions defaults: false do |conversation|
        item "Delete", admin_conversation_path(conversation), method: :delete, data: { confirm: "Are you sure you want to delete this?" }
      end
    end
  end

  show do |conversation|
    scope = params[:scope] || "all"
    prev_conv = Conversation.public_send(scope).where("created_at < ?", conversation.created_at).order(created_at: :desc).first
    next_conv = Conversation.public_send(scope).where("created_at > ?", conversation.created_at).order(created_at: :asc).first

    panel 'Navigation', class: 'navigation-buttons' do
      div do
        span class: 'navigation-button' do
          if next_conv.present?
            link_to('Newer', admin_conversation_path(next_conv, scope: scope), class: "button")
          else
            link_to('Newer', '#', class: "button disabled", onclick: "return false;")
          end
        end

        span class: 'navigation-button' do
          if prev_conv.present?
            link_to('Older', admin_conversation_path(prev_conv, scope: scope), class: "button")
          else
            link_to('Older', '#', class: "button disabled", onclick: "return false;")
          end
        end
      end
    end

    panel "Messages" do
      # use highlight_feedback() to highlight feedback column depending on its value
      table_for conversation.messages.order(:created_at), class: 'conversation_message_table', row_class: ->msg { highlight_feedback(msg) } do
        message_columns
      end
    end

  end

  sidebar "Info", only: [:show] do
    attributes_table_for conversation do
      row 'Start', &:created_at
      row 'End' do
        conversation.messages.last.created_at
      end
      row 'Status', &:status
      row 'Masdif', &:masdif_version
    end
  end
end
