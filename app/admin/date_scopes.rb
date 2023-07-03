# app/admin/date_scopes.rb
# It's included in the AA resource files that need it and are meant to be used everywhere you want the same date scopes
module DateScopes
  def self.included(base)
    base.instance_exec do
      scope :all, default: true
      scope :today, group: :date
      scope :this_week, group: :date
      scope :this_month, group: :date
      scope :last_30_days, group: :date
      scope :this_year, group: :date
    end
  end
end

