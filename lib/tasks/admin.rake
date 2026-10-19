namespace :admin do
  desc "Create the sole type of user: an administrator (ADMIN_EMAIL, ADMIN_PASSWORD)"
  task create: :environment do
    email = ENV.fetch("ADMIN_EMAIL")
    password = ENV.fetch("ADMIN_PASSWORD")
    abort "Use at least 12 characters" if password.length < 12
    user = User.find_or_initialize_by(email_address: email.strip.downcase)
    abort "Administrator already exists; use password reset instead" if user.persisted?
    user.update!(password: password, password_confirmation: password)
    puts "Administrator created. Sign in at /session/new"
  end
end
