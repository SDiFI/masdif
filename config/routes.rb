Rails.application.routes.draw do
  resources :conversations
  # Define your application routes per the DSL in https://guides.rubyonrails.org/routing.html

  # defines the route for the health check
  get '/health', to: 'health#index'

  # defines the route for the cors options
  match '/', to: 'cors#options', via: :options
end
