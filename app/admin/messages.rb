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

  # Filter settings, preserve defaults and remove the ones we don't want
  preserve_default_filters!
  remove_filter :id, :updated_at, :meta_data, :conversation, :tts_result,
                :asr_audio_attachment, :tts_audio_attachments, :asr_audio_blob, :tts_audio_blobs
  filter :feedback, as: :select, collection: -> { %w[positive negative none] }

  # Customize index view
  index do
    selectable_column
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
