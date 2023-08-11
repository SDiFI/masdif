module SharedMessageDefs
  extend ActiveSupport::Concern

  # Define the message columns of a messages table
  def message_columns
    column 'User text' do |m|
      if current_user.admin?
        # only show message details for admin users
        link_to m.text, admin_message_path(m, scope: params[:scope])
      else
        m.text
      end
    end
    column 'Bot answer', :reply_text
    # CSS highlighting rules apply to 'col-user_feedback' column
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

  # Return the CSS row_class to highlight the feedback
  #
  # @param [Message] msg the message
  # @return [String] the CSS class
  def highlight_feedback(msg)
    if msg.feedback == 'positive'
      'highlight-positive'
    elsif msg.feedback == 'negative'
      'highlight-negative'
    else
      'highlight-none'
    end
  end
end
