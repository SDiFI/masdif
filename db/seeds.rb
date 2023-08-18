# Seed the database with initial data

# prepopulate roles
%w[user admin].each do |role|
  Role.create!(name: role)
end

admin_role = Role.find_by(name: :'admin')
if admin_role.nil?
  raise "Could not find admin role ?!"
end

# Create a dummy default admin user for the admin interface in development
if Rails.env.development?
  User.create!(email: 'admin@example.com', password: 'password', password_confirmation: 'password', role: admin_role)
elsif Rails.env.production?
  # For production, we want to make sure that we never create a default admin user. Therefore it needs to be explicitly
  # created via environment variables or Rails credentials. You can change this later in the admin interface.
  admin_user = Rails.application.credentials&.admin_user || ENV['ADMIN_USER']
  admin_password = Rails.application.credentials&.admin_password || ENV['ADMIN_PASSWORD']
  if admin_user && admin_password
    User.create!(email: admin_user, password: admin_password, password_confirmation: admin_password, role: admin_role)
  else
    raise "Missing ADMIN_USER and ADMIN_PASSWORD environment variables, or Rails credentials."
  end
end
