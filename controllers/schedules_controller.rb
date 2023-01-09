class SchedulesController < ApplicationController
  before_action :authenticate_account!

  def show
    @calendar_date = params.fetch(:start_date, Time.now).to_time

    # in our instance we need to get to variables that we plot on the calendar
    @combined_calendar_events = @programmes + @module_instances

    @accounts = Account.order_by_full_name.load_async
  end

  def availability_spinner
    render turbo_stream: turbo_stream.replace(:scheduling_calendar_sidebar, partial: 'schedules/partials/scheduling_calendar_sidebar_spinner', locals: {
      date: params[:date],
    })
  end

  def availability
    @calendar_date = params[:date].to_datetime

    @account_statuses = Account.visible_and_active_facilitators_and_admins(includes: current_account.id).includes([:availability_rules]).order_by_full_name.collect do |account|
      { name: account.name, status: ScheduledStatus.new(account: account, start_time: @calendar_date).check_status }
    end

    render turbo_stream: turbo_stream.replace(:scheduling_calendar_sidebar_spinner, partial: 'schedules/partials/scheduling_calendar_sidebar')
  end
end
