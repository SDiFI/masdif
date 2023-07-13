module ActiveAdmin
  module ScopesPersistence
    extend ActiveSupport::Concern

    SCOPE = "scope"
    DEFAULT_SCOPE = "all"

    included do
      before_action :resolve_scopes
    end

    private

    def resolve_scopes
      session_key = "aa_scope".to_sym

      if (params[:scope] || params[:commit] == SCOPE) && action_name.inquiry.index?
        session[session_key] = params[:scope]
      elsif session[session_key].nil? && action_name.inquiry.index?
        session[session_key] = DEFAULT_SCOPE
      elsif session[session_key] && action_name.inquiry.index?
        params[:scope] = session[session_key]
      end
    end
  end
end
