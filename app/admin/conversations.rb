ActiveAdmin.register Conversation do

  # See permitted parameters documentation:
  # https://github.com/activeadmin/activeadmin/blob/master/docs/2-resource-customization.md#setting-up-strong-parameters
  #
  # Uncomment all parameters which should be permitted for assignment
  #
  # permit_params :status
  #
  # or
  #
  # permit_params do
  #   permitted = [:status]
  #   permitted << :other if params[:action] == 'create' && current_user.admin?
  #   permitted
  # end

  include DateScopes

  config.sort_order = 'created_at_desc'

  actions :all, :except => [:new, :create, :edit]

  preserve_default_filters!
  remove_filter :updated_at

  index do
    selectable_column
    column :id do |conversation|
      link_to conversation.id, admin_conversation_path(conversation, scope: params[:scope])
    end
    column :created_at
    column :updated_at
    column :status

    actions defaults: false do |conversation|
      item "Delete", admin_conversation_path(conversation), method: :delete, data: { confirm: "Are you sure you want to delete this?" }
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
      table_for conversation.messages.order(:created_at) do
        column 'User' do |m|
          link_to m.text, admin_message_path(m, scope: params[:scope])
        end
        column 'Bot', :reply_text
        column :feedback
        column 'Intent', :intent
        column 'Entities', :entities
        column 'Slots', :slots
        column 'Actions', :actions
        column 'Audio' do |m|
          audio_urls = m.audio_urls
          if audio_urls.nil? || audio_urls.empty?
            'N/A'
          else
            audio_tag audio_urls, controls: true, preload: 'none'
          end
        end
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
    end
  end
end
