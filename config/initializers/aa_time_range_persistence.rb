module ActiveAdmin
  module TimeRangesPersistence
    extend ActiveSupport::Concern

    TIME_RANGE = "time_range"
    DEFAULT_TIME_RANGE = "last_30_days"

    included do
      before_action :resolve_time_ranges
    end

    private

    def resolve_time_ranges
      session_key = "#{controller_name}_time_range".to_sym

      if params[:time_range] && action_name.inquiry.index?
        session[session_key] = params[:time_range]
      elsif session[session_key] && action_name.inquiry.index?
        params[:time_range] = session[session_key]
      elsif session[session_key].nil? && action_name.inquiry.index?
        session[:session_key] = params[:time_range] = DEFAULT_TIME_RANGE
      end
    end
  end
end
