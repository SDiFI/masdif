module ActiveAdmin
  module PaginationPersistence
    extend ActiveSupport::Concern

    DEFAULT_PAGINATION = "50"

    included do
      before_action :resolve_pagination
    end

    private

    def resolve_pagination
      session_key = "aa_pagination".to_sym

      if params[:per_page] && action_name.inquiry.index?
        session[session_key] = params[:per_page]
        Rails.logger.debug "Setting session[#{session_key}] to #{params[:per_page]}"
      elsif session[session_key] && action_name.inquiry.index?
        params[:per_page] = session[session_key]
        Rails.logger.debug "Setting params[:per_page] to #{session[session_key]}"
      elsif session[session_key].nil? && action_name.inquiry.index?
        session[:session_key] = params[:per_page] = DEFAULT_PAGINATION
        Rails.logger.debug "Setting session[#{session_key}] to #{DEFAULT_PAGINATION}"
      end
    end
  end
end
