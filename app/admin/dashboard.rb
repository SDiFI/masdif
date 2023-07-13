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
    feedback_counts = Message.feedback_counts(time_range)

    panel "Stats" do
      columns do
        column do
          if feedback_counts.empty?
            h3 "No data"
          else
            m_stats = {Overall: feedback_counts['overall'], ASR: counts[:asr_count], TTS: counts[:tts_count]}
            table class: 'index_table' do
              tr do
                th 'Messages'
                th 'Count'
              end
              m_stats.each do |message, count|
                tr do
                  td message
                  td count
                end
              end
            end
          end
        end

        column do
          if feedback_counts.empty? && !feedback_counts.present?
            h3 "No data"
            next
          else
            table class: 'index_table' do
              tr do
                th 'Feedback'
                th 'Count'
              end
              feedback_counts.each do |feedback, count|
                next if feedback == 'overall'
                tr do
                  td feedback
                  td count
                end
              end
            end
          end
        end
      end
    end

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
          grouping = case time_range
                     when 'today'
                       {method: :group_by_hour, params: [:created_at]}
                     else
                       {method: :group_by_day, params: [:created_at]}
                     end
          total = Message.send(time_range).where("text NOT LIKE ?", '/%').send(grouping[:method], *grouping[:params]).count

          if total.empty?
            h3 "No data"
          else
            case grouping[:method]
            when :group_by_hour
              period = 'hour'
            else
              period = 'day'
            end
            fb_series = Message.feedback_date_series(time_range, period)
            total_series = { name: "Total", data: total }

            # Define the series order & sort fb_series by name
            fb_series.sort_by! { |series| %w[positive negative].index(series[:name]) || Float::INFINITY }

            # Colors order is important and needs to match fb_series order as we want to show positive as green, negative
            # as red and Total in a nice palette color !
            colors = %w[green red #008FFB] # colors for positive, negative and total
            chart_options = { colors: colors, stacked: false, data_labels: false }
            render partial: 'activity_chart', locals: { fb_series: fb_series, total_series: total_series, options: chart_options }
          end
        end
      end
    end

  end # content
end
