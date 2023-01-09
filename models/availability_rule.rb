# == Schema Information
#
# Table name: availability_rules
#
#  id                :integer          not null, primary key
#  availability_type :integer          not null
#  start_time        :datetime         not null
#  end_time          :datetime
#  repeat_type       :integer          not null
#  frequency         :integer          default("0"), not null
#  raw_rule          :jsonb
#  bookable_type     :string
#  bookable_id       :integer
#  account_id        :integer          not null
#  created_at        :datetime         not null
#  updated_at        :datetime         not null
#
# Indexes
#
#  index_availability_rules_on_account_id         (account_id)
#  index_availability_rules_on_availability_type  (availability_type)
#  index_availability_rules_on_bookable           (bookable_type,bookable_id)
#  index_availability_rules_on_end_time           (end_time)
#  index_availability_rules_on_start_time         (start_time)
#

class AvailabilityRule < ApplicationRecord
  belongs_to :bookable, polymorphic: true, optional: true
  belongs_to :account

  has_many :availability_rule_exceptions, dependent: :destroy

  enum availability_type: { available: 0, unavailable: 1, booked: 2 }
  enum repeat_type: { one_off: 0, weekly: 1, monthly: 2 }

  attr_accessor :desired_exception_time

  validates_presence_of :availability_type, :repeat_type, :start_time
  validates_presence_of :bookable, if: :booked?

  validates_comparison_of :end_time, greater_than_or_equal_to: :start_time, allow_nil: true, if: :start_time?

  validates_numericality_of :frequency, greater_than_or_equal_to: 1, unless: :one_off?

  before_validation :set_attributes_for_one_off, if: :one_off?, unless: :booked?
  before_validation :set_times
  before_validation :unset_bookable, unless: :booked?
  before_save :set_raw_rule, unless: :one_off?

  # possible bookable types are 'ModuleInstance' or 'Programme'
  def bookable_module_instance?
    self.bookable_type == 'ModuleInstance'
  end

  # generate events for the visible calendar, including previous and next month days
  def calendar_events(start)
    if self.one_off?
      [self]
    else
      calendar_start_date = start.beginning_of_month.beginning_of_week
      start_date = calendar_start_date > self.start_time ? calendar_start_date : self.start_time

      calendar_end_date = start.end_of_month.end_of_week
      end_date = (self.end_time.blank? || calendar_end_date < self.end_time) ? calendar_end_date : self.end_time

      schedule(start_date).occurrences(end_date).map do |date|
        AvailabilityRule.new(
          id: self.id,
          repeat_type: self.repeat_type,
          start_time: date,
          end_time: date.end_of_day,
          availability_type: self.availability_type,
          bookable_id: self.bookable_id,
          bookable_type: self.bookable_type,
        )
      end
    end
  end

  def all_calendar_events
    if self.one_off?
      [self]
    else
      schedule(self.start_time).occurrences(self.end_time).map do |date|
        AvailabilityRule.new(
          id: self.id,
          repeat_type: self.repeat_type,
          start_time: date,
          end_time: date.end_of_day,
          availability_type: self.availability_type,
          bookable_id: self.bookable_id,
          bookable_type: self.bookable_type,
        )
      end
    end
  end

  def sort_by_priority
    if self.booked?
      -1
    else
      self.unavailable? ? 0 : 1
    end
  end

  def rule
    IceCube::Rule.from_hash(self.raw_rule)
  end

  private

  def set_attributes_for_one_off
    self.end_time = self.start_time if self.end_time.blank?
    self.frequency = 0
  end

  def set_times
    # moves times into UTC as these are date based and not time
    Time.zone = 'UTC'
    self.start_time = self.start_time.beginning_of_day if self.start_time.present?
    self.end_time = self.end_time.end_of_day if self.end_time.present?
  end

  def unset_bookable
    self.bookable = nil
  end

  def set_raw_rule
    self.raw_rule = { interval: self.frequency, week_start: 0 }

    case self.repeat_type
    when 'weekly'
      self.raw_rule[:rule_type] = 'IceCube::WeeklyRule'
      self.raw_rule[:validations] = { day: [self.start_time.wday] }
    when 'monthly'
      self.raw_rule[:rule_type] = 'IceCube::MonthlyRule'
      self.raw_rule[:validations] = { day_of_month: [self.start_time.day] }
    end
  end

  def schedule(start)
    schedule = IceCube::Schedule.new(start)
    schedule.add_recurrence_rule(self.rule)

    self.availability_rule_exceptions.each do |exception|
      schedule.add_exception_time(exception.exception_time)
    end

    schedule
  end
end
