class AvailabilitiesController < ApplicationController
  before_action :authenticate_account!

  def index
    # resets timezone to UTC to display dates on correct day
    Time.zone = 'UTC'

    calendar_date = params.fetch(:start_date, Time.now).to_time

    @availabilities = current_account
      .availability_rules
      .includes([:bookable])
      .where(end_time: [calendar_date.beginning_of_month.beginning_of_week.beginning_of_day.., nil], start_time: ..calendar_date.end_of_month.end_of_week.end_of_day)
      .load_async
      .flat_map { |availability_rule| availability_rule.calendar_events(params.fetch(:start_date, Time.zone.now).to_date) }

    @repeating_availabilities = current_account
      .availability_rules
      .not_one_off.where(end_time: [Time.now.., nil])
      .load_async
      .sort_by(&:sort_by_priority)
  end

  def new
    availability_rule = AvailabilityRule.new(frequency: 1)

    render turbo_stream: turbo_stream.append(:modals, partial: 'availability_rule_modal', locals: { availability_rule: availability_rule, start_date: params[:start_date] })
  end

  def create
    # resets timezone to UTC to display dates on correct day
    Time.zone = 'UTC'

    availability_rule = AvailabilityRule.new(availability_rule_params)
    availability_rule.account = current_account

    if availability_rule.save
      flash[:success] = 'Successfully set your availability'
      redirect_to availabilities_path(start_date: params[:start_date])
    else
      render turbo_stream: [
        turbo_stream.replace(availability_rule, partial: 'availability_rule_modal', locals: { availability_rule: availability_rule, start_date: params[:start_date] }),
        turbo_stream.append(:toasts, partial: 'partials/toast', locals: {
          timeout: 5000,
          key: :danger,
          value: 'Something went wrong setting your availability. Please try again.',
        }),
      ]
    end
  end

  # used for:
  # - deleting repeating availabilities
  # - deleting one off availabilities
  # - creating exception rules for repeating availabilities
  def destroy
    availability_rule = AvailabilityRule.find(params[:id])
    availability_rule.desired_exception_time = params[:start_time].to_datetime if params[:start_time].present?
    authorize availability_rule

    if !availability_rule.one_off? && availability_rule.desired_exception_time.present?
      # destroy the availability if exceptions are created for all occurrences
      if availability_rule.end_time.present? && availability_rule.all_calendar_events.size == 1
        success = !!availability_rule.destroy
      else
        availability_rule_exception = availability_rule.availability_rule_exceptions.new(exception_time: availability_rule.desired_exception_time)
        success = availability_rule_exception.save
      end
    else
      success = !!availability_rule.destroy
    end

    if success
      flash[:success] = 'Successfully deleted your availability'
    else
      flash[:danger] = 'Something went wrong deleting the availability. Please try again.'
    end

    redirect_back fallback_location: availabilities_path
  end

  # used to get each account availability on a specific day
  def accounts
    start_time = params[:start_time].present? ? params[:start_time].to_datetime : Time.now
    end_time = params[:end_time].present? ? params[:end_time].to_datetime : start_time

    bookable_id = params[:bookable]&.scan(/\d+$/)&.first
    bookable_type = params[:bookable]&.gsub(/\d+$/, '')&.include?('programme') ? 'Programme' : params[:bookable].gsub(/\d+$/, '').camelcase

    availabilities = Account.not_participant.active.collect do |account|
      {
        account_id: account.id,
        utilisation: account.month_utilisations.find_by(date: start_time.beginning_of_month),
        status: ScheduledStatus.new(account: account, start_time: start_time, end_time: end_time, bookable_id: bookable_id, bookable_type: bookable_type).check_status,
      }
    end

    renders = availabilities.collect do |availability|
      [
        turbo_stream.replace("#{params[:bookable]}_account_#{availability[:account_id]}_availability", partial: 'availabilities/account_availability', locals: {
          bookable: params[:bookable],
          bookable_type: bookable_type,
          availability: availability,
        }),
        turbo_stream.replace("#{params[:bookable]}_account_#{availability[:account_id]}_utilisation", partial: 'availabilities/account_utilisation', locals: {
          bookable: params[:bookable],
          availability: availability,
          bookable_type: bookable_type,
        }),
      ]
    end.flatten

    render turbo_stream: renders
  end

  private

  def availability_rule_params
    params.require(:availability_rule).permit(:availability_type, :start_time, :end_time, :repeat_type, :frequency)
  end
end
