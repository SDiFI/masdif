# frozen_string_literal: true
module ActiveAdmin
  module Views
    class Header < Component

      def build(namespace, menu)
        super(id: "header")

        @namespace = namespace
        @menu = menu
        @utility_menu = @namespace.fetch_menu(:utility_navigation)
        # Add the application version to the site title
        @namespace.site_title = "#{ActiveAdmin.application.site_title} - #{app_version}"
        site_title @namespace
        global_navigation @menu, class: "header-item tabs"
        utility_navigation @utility_menu, id: "utility_nav", class: "header-item tabs"
      end

    end
  end
end
