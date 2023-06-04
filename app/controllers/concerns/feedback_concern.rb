# frozen_string_literal: true

module FeedbackConcern
  extend ActiveSupport::Concern

  included do

    # Sets @feedback object if provided in the request parameters.
    # In case the provided feedback parameters are invalid, @feedback_error is set to true.
    def set_feedback
      feedback_value = Message.parse_feedback(conversation_params[:text]&.to_s)
      message_id = conversation_params[:message_id]
      if feedback_value
        if update_feedback(feedback_value, message_id.to_s)
          @feedback = { value: feedback_value }
          @feedback[:message_id] = message_id.to_s
          do_fwd, msg_text = build_feedback_message(message_id.to_s, feedback_value)
          @feedback[:do_forward] = do_fwd
          @feedback[:text] = msg_text
        else
          @feedback_error = true
        end
      elsif message_id
        @feedback_error = true
        # only valid in combination with /feedback{"value": "some_value"}
        logger.warn "Provided message_id: #{message_id} without feedback value"
        render json: {error: 'message_id provided without feedback value'}, status: :bad_request
      end
    end

    # Builds the feedback message to be sent to the dialog system
    #
    # @param message_id [String] the message ID
    # @param feedback_value [String, nil] the feedback value
    # @return [Array] [do_fwd, message_text] where do_fwd is true if the feedback should be forwarded to the
    #                                        dialog system and message_text is the encoded text to be sent to
    #                                        the dialog system
    def build_feedback_message(message_id, feedback_value)
      do_fwd = false
      message_text = nil
      # replace text with the specified intent & feedback value
      if feedback_value
        # examine configuration and build feedback for the dialog system
        config = Rails.application.config.masdif[:feedback]
        if config && config[:forward]
          do_fwd = true
          intent = config[:intent]
          message_text = "/#{intent}{\"value\": \"#{feedback_value}\""
          if config[:include_reply_text] == true
            message = @conversation.messages.find_by(id: message_id)
            # message existence has been checked beforehand
            reply_text = JSON.parse(message.reply)&.collect { |reply| reply['text'] }&.join('.')
            if reply_text
              message_text += ", \"text\": \"#{reply_text}\""
            end
          end
          message_text += "}"
        end
      end
      [do_fwd, message_text]
    end

    # Updates the feedback value of a message in case the user has clicked on a feedback button.
    # @param [String] feedback_value value of the feedback button
    # @param [String] message_id ID of the message that was clicked on
    # @return [Boolean] true if feedback was updated, false otherwise
    def update_feedback(feedback_value, message_id)
      rv = false
      if feedback_value
        if feedback_value == 'invalid'
          msg = "Malformed feedback value detected"
          logger.warn msg
          render json: { error: msg }, status: :bad_request
        else
          if message_id&.size >0
            message = @conversation.messages.find_by(id: message_id)
            if message
              message.update!(feedback: feedback_value)
              rv = true
            else
              msg = "Message not found: #{message_id}"
              logger.warn msg
              render json: { error: msg }, status: :not_found
            end
          else
            msg = "Missing message_id"
            logger.warn msg
            render json: { error: msg }, status: :bad_request
          end
        end
      end
      rv
    end

  end
end
