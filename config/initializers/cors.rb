Rails.application.config.middleware.insert_before 0, Rack::Cors do
  allow do
    origins '*'
    resource '*',
    headers: :any,
    methods: [:get, :patch, :post, :put, :delete, :options],
    expose: ['Authorization'],
    max_age: 1728000
  end
end