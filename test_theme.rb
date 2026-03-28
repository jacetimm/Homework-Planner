require_relative 'config/environment'
setting = UserSetting.last
puts "DB color_theme: #{setting.color_theme}"
puts "DB onboarding_completed: #{setting.onboarding_completed}"
