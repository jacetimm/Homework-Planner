module DashboardHelper
  def format_due_date(date)
    return "No due date" if date.nil?

    date_only = date.to_date
    if date.to_date == Date.current
      date.is_a?(Time) ? "Today at #{date.strftime('%l:%M %p').strip}" : "Today"
    elsif date.to_date == Date.current.tomorrow
      date.is_a?(Time) ? "Tomorrow at #{date.strftime('%l:%M %p').strip}" : "Tomorrow"
    else
      date_only.strftime("%b %-d, %Y")
    end
  end

  def urgency_color_class(date)
    return "bg-gray-100 text-gray-800" if date.nil?

    days_until_due = (date.to_date - Date.current).to_i

    if days_until_due < 0
      "bg-red-100 text-red-800 border border-red-200" # Overdue
    elsif days_until_due <= 1
      "bg-amber-100 text-amber-800 border border-amber-200" # Due soon (today/tomorrow)
    else
      "bg-emerald-100 text-emerald-800 border border-emerald-200" # Normal
    end
  end

  def urgency_icon(date)
    return "" if date.nil?

    days_until_due = (date.to_date - Date.current).to_i

    if days_until_due < 0
      "<svg xmlns='http://www.w3.org/2000/svg' class='h-4 w-4 mr-1' fill='none' viewBox='0 0 24 24' stroke='currentColor'><path stroke-linecap='round' stroke-linejoin='round' stroke-width='2' d='M12 8v4m0 4h.01M21 12a9 9 0 11-18 0 9 9 0 0118 0z' /></svg>".html_safe
    elsif days_until_due <= 1
      "<svg xmlns='http://www.w3.org/2000/svg' class='h-4 w-4 mr-1' fill='none' viewBox='0 0 24 24' stroke='currentColor'><path stroke-linecap='round' stroke-linejoin='round' stroke-width='2' d='M12 8v4l3 3m6-3a9 9 0 11-18 0 9 9 0 0118 0z' /></svg>".html_safe
    else
      "<svg xmlns='http://www.w3.org/2000/svg' class='h-4 w-4 mr-1' fill='none' viewBox='0 0 24 24' stroke='currentColor'><path stroke-linecap='round' stroke-linejoin='round' stroke-width='2' d='M8 7V3m8 4V3m-9 8h10M5 21h14a2 2 0 002-2V7a2 2 0 00-2-2H5a2 2 0 00-2 2v12a2 2 0 002 2z' /></svg>".html_safe
    end
  end
end
