# app/models/concerns/time_scopes.rb
module TimeScopes
  extend ActiveSupport::Concern

  included do
    scope :today, -> { where(created_at: Date.today.all_day) }
    scope :this_week, -> { where(created_at: Date.today.all_week) }
    scope :this_month, -> { where(created_at: Date.today.all_month) }
    scope :this_year, -> { where(created_at: Date.today.all_year) }
    scope :month , ->(month) { where(created_at: month.beginning_of_month..month.end_of_month) }
    scope :last_n_months, ->(n) { where(created_at: n.months.ago.beginning_of_month..Time.zone.now.end_of_month) }
    scope :last_n_years, ->(n) { where(created_at: n.years.ago.beginning_of_year..Time.zone.now.end_of_year) }
    scope :last_n_days, ->(n) { where(created_at: n.days.ago.beginning_of_day..Time.zone.now.end_of_day) }
    scope :last_30_days, -> { last_n_days(30) }
  end
end
