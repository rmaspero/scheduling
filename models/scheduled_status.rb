class ScheduledStatus
  include ActiveModel::Model

  attr_accessor :account, :start_time, :end_time, :bookable_type, :bookable_id

  validates_presence_of :account, :start_time

  def check_status
    Time.zone = 'UTC'
    check_start_time = self.start_time.beginning_of_day
    check_end_time = self.end_time&.end_of_day || self.start_time.end_of_day

    # gets all rules that fall, or may fall on the day
    # one-off rules that start or end on the day, or start/end either side of it and hence must happen on the day
    one_off_rules_on_day = account.availability_rules.one_off.where(start_time: check_start_time..check_end_time)
      .or(account.availability_rules.one_off.where(end_time: check_start_time..check_end_time))
      .or(account.availability_rules.one_off.where(start_time: ...check_start_time, end_time: check_end_time...))

    # repeating rules that start on the day or earlier and haven't finished, so can and may be in effect on the day
    repeating_rules_on_day = account.availability_rules.not_one_off.where(start_time: ..check_end_time).where.not(end_time: ...check_start_time)
      .or(account.availability_rules.not_one_off.where(start_time: ..check_end_time).where(end_time: nil))

    # when picking a facilitator for a programme we pass the booking we are looking at to exclude any rules related to that programme
    # this means that a facilitator is not noted as booked in the selection modal for the programme that is currently being edited
    # this reduces confusion so the editor believes they can place the facilitor on the programme they have already been placed on
    if self.bookable_id.present? && self.bookable_type.present?
      one_off_rules_on_day = AvailabilityRule.where(id: one_off_rules_on_day.select(:id))
        .where.not(bookable_id: self.bookable_id, bookable_type: self.bookable_type)
        .or(AvailabilityRule.where(id: one_off_rules_on_day.select(:id)).where(bookable_id: nil, bookable_type: nil))

      repeating_rules_on_day = repeating_rules_on_day.where.not(bookable_id: self.bookable_id, bookable_type: self.bookable_type)
        .or(repeating_rules_on_day.where(bookable_id: nil, bookable_type: nil))
    end

    # sort by priority and get the first type to get the highest priority value for the day
    one_off_rules_on_day_priority = one_off_rules_on_day&.sort_by(&:sort_by_priority)&.first&.availability_type

    # if they have no rules today, their status is standby
    if one_off_rules_on_day_priority.blank? && repeating_rules_on_day.empty?
      return 'standby'
    end

    # if they have a one-off booked rule on the day, their status is booked
    return 'booked' if one_off_rules_on_day_priority == 'booked'

    # if they have any repeating booked rules (unlikely) that may fall on the day, find the occurrences to see if any do fall on the day
    # exceptions negate the rule
    booked_rules = repeating_rules_on_day.select(&:booked?)
    if booked_rules.present?
      booked_schedule = IceCube::Schedule.new((check_start_time - 1.day).to_time)
      booked_rules.each do |booked_rule|
        booked_schedule.add_recurrence_rule(booked_rule.rule)

        booked_rule.availability_rule_exceptions.each do |exception|
          booked_schedule.add_exception_time(exception.exception_time)
        end
      end

      # if they have a repeating booked rule that occurs on the day, their status is booked
      return 'booked' if booked_schedule.occurs_between?(check_start_time, check_end_time)
    end

    # if they have a one-off unavailable rule on the day, their status is unavailable
    return 'unavailable' if one_off_rules_on_day_priority == 'unavailable'

    # if they have any repeating unavailable rules that may fall on the day, find the occurrences to see if any do fall on the day
    unavailable_rules = repeating_rules_on_day.select(&:unavailable?)
    if unavailable_rules.present?
      unavailable_schedule = IceCube::Schedule.new((check_start_time - 1.day).to_time)
      unavailable_rules.each do |unavailable_rule|
        unavailable_schedule.add_recurrence_rule(unavailable_rule.rule)

        unavailable_rule.availability_rule_exceptions.each do |exception|
          unavailable_schedule.add_exception_time(exception.exception_time)
        end
      end

      # if they have a repeating unavailable rule that occurs in between the start and end days, their status is unavailable
      return 'unavailable' if unavailable_schedule.occurs_between?(check_start_time, check_end_time)
    end

    # if they have a one-off available rule on the day, their status is unavailable
    return 'available' if one_off_rules_on_day_priority == 'available'

    # if they have any repeating available rules that may fall on the day, find the occurrences to see if any do fall on the day
    available_rules = repeating_rules_on_day.select(&:available?)
    if available_rules.present?
      available_schedule = IceCube::Schedule.new((check_start_time - 1.day).to_time)
      available_rules.each do |available_rule|
        available_schedule.add_recurrence_rule(available_rule.rule)

        available_rule.availability_rule_exceptions.each do |exception|
          available_schedule.add_exception_time(exception.exception_time)
        end
      end

      # if they have a repeating available rule that occurs in between the start and end days, their status is unavailable
      return 'available' if available_schedule.occurs_between?(check_start_time, check_end_time)
    end

    # if none of their rules occur on the day, their status is unavailable
    'standby'
  end
end
