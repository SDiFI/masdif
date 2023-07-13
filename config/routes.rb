Rails.application.routes.draw do
  # Define your application routes per the DSL in https://guides.rubyonrails.org/routing.html

  # enable routes for admin interface if enabled in config
  if Rails.application.config.masdif&.dig(:admin_interface, :enabled)
    devise_for :users, ActiveAdmin::Devise.config
    ActiveAdmin.routes(self)
  end

  # Chat widget route to ChatController
  chat_widget_config = Rails.application.config.masdif&.dig(:chat_widget)
  if chat_widget_config[:enabled]
    get chat_widget_config[:path], to: 'chat#index'
    if chat_widget_config[:path] == '/'
      root to: 'chat#index'
    end
  end

  resources :conversations, only: [:create, :update]

  get '/info', to: 'info#index'

  # defines the route for the health check
  get '/health', to: 'health#index'

  # defines the route for the version
  get '/version', to: 'version#show'

  # defines the route for the cors options
  match '/', to: 'cors#options', via: :options
end
