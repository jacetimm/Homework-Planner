require_relative "boot"

require "rails/all"

# Require the gems listed in Gemfile, including any gems
# you've limited to :test, :development, or :production.
Bundler.require(*Rails.groups)

module HomeworkPlanner
  class Application < Rails::Application
    # Initialize configuration defaults for originally generated Rails version.
    config.load_defaults 7.2

    # Please, add to the `ignore` list any other `lib` subdirectories that do
    # not contain `.rb` files, or that should not be reloaded or eager loaded.
    # Common ones are `templates`, `generators`, or `middleware`, for example.
    config.autoload_lib(ignore: %w[assets tasks])

    # Configuration for the application, engines, and railties goes here.
    #
    # These settings can be overridden in specific environments using the files
    # in config/environments, which are processed later.
    #
    config.time_zone = "America/New_York"
    config.active_record.default_timezone = :utc
    config.active_record.time_zone_aware_attributes = true

    # ActiveRecord Encryption for storing OAuth tokens on the User model.
    # Override with real random values via ENV in production.
    config.active_record.encryption.primary_key        = ENV.fetch("AR_ENC_PRIMARY_KEY",        "iocrqWcV17dpRUwL91SbKjTvmF4GZc8z")
    config.active_record.encryption.deterministic_key  = ENV.fetch("AR_ENC_DETERMINISTIC_KEY",  "QTCTNMTACECMn1ewlggmLKkOWsjoSo7E")
    config.active_record.encryption.key_derivation_salt = ENV.fetch("AR_ENC_KEY_DERIVATION_SALT", "ugegme6Gb7QiJPjKxspBCamNeZxM5Hue")

    # config.eager_load_paths << Rails.root.join("extras")
  end
end
