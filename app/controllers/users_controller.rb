class UsersController < ApplicationController
  # PATCH /users/timezone
  # Accepts an IANA timezone name (e.g. "America/Chicago") from the browser's
  # Intl API and converts it to the matching ActiveSupport zone name before saving.
  def set_timezone
    return head :unauthorized unless current_user

    iana_name = params[:timezone].to_s.strip
    # Match IANA identifier (e.g. "America/Chicago") to an ActiveSupport zone so
    # the stored name ("Central Time (US & Canada)") stays consistent with the
    # dropdown values and the migration default.
    as_zone = ActiveSupport::TimeZone.all.find { |z| z.tzinfo.identifier == iana_name }

    if as_zone
      current_user.update!(timezone: as_zone.name)
      head :ok
    else
      head :unprocessable_entity
    end
  end
end
