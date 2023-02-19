Rails.application.routes.draw do
  resources :conversations
  # Define your application routes per the DSL in https://guides.rubyonrails.org/routing.html

  # Defines the root path route ("/")
  # root "articles#index"

  # defines the route for the health check
  get '/health', to: 'health#index'
end
