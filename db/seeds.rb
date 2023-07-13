# This file should contain all the record creation needed to seed the database with its default values.
# The data can then be loaded with the bin/rails db:seed command (or created alongside the database with db:setup).
#
# Examples:
#
#   movies = Movie.create([{ name: "Star Wars" }, { name: "Lord of the Rings" }])
#   Character.create(name: "Luke", movie: movies.first)

# Create a dummy default admin user for the admin interface in development
User.create!(email: 'admin@example.com', password: 'password', password_confirmation: 'password') if Rails.env.development?

# For production, we want to make sure that we never create a default admin user. Therefore it needs to be explicitly
# created via environment variables or Rails credentials.
if Rails.env.production?
  admin_user = Rails.credentials&.admin_user || ENV['ADMIN_USER']
  admin_password = Rails.credentials&.admin_password || ENV['ADMIN_PASSWORD']
  if admin_user && admin_password
    User.create!(email: admin_user, password: admin_password, password_confirmation: admin_password)
  else
    raise "Missing ADMIN_USER and ADMIN_PASSWORD environment variables, or Rails credentials."
  end
end