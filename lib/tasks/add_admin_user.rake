namespace :admin do
  desc 'Add admin user with ADMIN_USER and ADMIN_PASSWORD environment variables or arguments'
  task :add, [:email, :password] => :environment do |t, args|
    args.with_defaults(:email => ENV['ADMIN_USER'], :password => :ENV['ADMIN_PASSWORD'])
    email = args[:email]
    password = args[:password]
    user = User.find_or_create_by!(email: email) do |user|
      user.password = password
      user.password_confirmation = password
      user.role = Role.find_by_name('admin')
    end
    puts "Admin user created: #{user.email}"
  end
end