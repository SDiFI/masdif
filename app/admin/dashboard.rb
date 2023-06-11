# frozen_string_literal: true
ActiveAdmin.register_page "Dashboard" do
  menu priority: 1, label: proc { I18n.t("active_admin.dashboard") }

  content title: proc { I18n.t("active_admin.dashboard") } do
    div class: "blank_slate_container", id: "dashboard_default_message" do
      span class: "blank_slate" do
        span I18n.t("active_admin.dashboard_welcome.welcome")
        small I18n.t("active_admin.dashboard_welcome.call_to_action")
      end
    end

    # Here is an example of a simple dashboard with columns and panels.
    #
    columns do
    #   column do
    #     panel "Recent Posts" do
    #       ul do
    #         Post.recent(5).map do |post|
    #           li link_to(post.title, admin_post_path(post))
    #         end
    #       end
    #     end
    #   end

    column do
        panel "Info" do
          para "Welcome to ActiveAdmin."
        end
      end
    end
=begin
    panel "Top stuff --all name-removed for brevity--" do
      # line_chart   Content.pluck("download").uniq.map { |c| { title: c, data: Content.where(download: c).group_by_day(:updated_at, format: "%B %d, %Y").count }  }, discrete: true
      # column_chart Content.group_by_hour_of_day(:updated_at, format: "%l %P").order(:download).count, {library: {title:'Downloads for all providers'}}
      # column_chart Content.group(:title).order('download DESC').limit(5).sum(:download)
      bar_chart Content.group(:title).order('download DESC').limit(5).sum(:download) ,{library: {title:'Top 5 Downloads'}}
      ##
      # line_chart result.each(:as => :hash) { |item|
      #   {name: item.title, data: item.sum_download.count}
      # }
    end
=end
  end # content
end
