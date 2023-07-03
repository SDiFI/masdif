# frozen_string_literal: true

ActiveAdmin.register_page "Dashboard" do
  menu priority: 1, label: proc { I18n.t("active_admin.dashboard") }

  content title: proc { I18n.t("active_admin.dashboard") } do

    time_range = params[:time_range] || 'last_30_days'

    form action: admin_dashboard_path, method: :get do
      select_tag :time_range,
                 options_for_select([['Today', 'today'],
                                     ['This week', :this_week],
                                     ['This month', :this_month],
                                     ['Last 30 days', :last_30_days],
                                     ['This year', :this_year],
                                     ['All', :all]],
                                    time_range),
                 onchange: 'this.form.submit();'
    end

    counts = Message.stats_counts(time_range)

    columns class: 'intent-entities-columns' do
      column do
        panel "Intents" do
          if counts[:intents_percentage].empty?
            h3 "No data"
            next
          end
          colors = %w[#df2e38 #e85538 #ee733c #f48f45 #f8a954 #fbc268 #ffda80 #e3d174 #c8c76b #adbd64 #92b25f #78a75b #5d9c59]
          pie_chart(counts[:intents_percentage], legend: true, colors: colors)
        end
      end

      column do
        panel "Entities" do
          if counts[:entities_percentage].empty?
            h3 "No data"
            next
          end
          colors = %w[#6527be #3853db #0072ef #008efa #00a7ff #00beff #24d4ff #44d9fa #5cddf4 #71e2f0 #84e6ec #96eae9 #a7ede7]
          pie_chart(counts[:entities_percentage], legend: true, colors: colors)
        end
      end

      column do
        panel "Actions" do
          if counts[:actions_percentage].empty?
            h3 "No data"
            next
          end
          colors = %w[#00876c #40966e #64a470 #86b275 #a6bf7c #c6cb86 #e6d893 #e9c985 #ecb97b #efa874 #ef9872 #ed8773 #e97777]
          donut_chart(counts[:actions_percentage], legend: true, colors: colors)
        end
      end
    end

    columns do
      column do
        panel "Activity" do
          total =
            case time_range
            when 'all'
              Message.group_by_week(:created_at).count
            when 'today'
              Message.send(:today).group_by_hour(:created_at).count
            when 'this_week'
              Message.send(:this_week).group_by_day(:created_at).count
            when 'this_month'
              Message.send(:this_month).group_by_day(:created_at).count
            when 'this_year'
              Message.send(:this_year).group_by_day(:created_at).count
            when 'last_30_days'
              Message.send(:last_30_days).group_by_day(:created_at).count
            else
              {}
            end
          if total.empty?
            h3 "No data"
          else
            total_series = {
              name: "Total", data: total
            }
            area_chart(total_series, theme: 'palette2')
          end
        end
      end
    end

  end # content
end
