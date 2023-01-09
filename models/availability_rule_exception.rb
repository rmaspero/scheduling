# == Schema Information
#
# Table name: availability_rule_exceptions
#
#  id                   :integer          not null, primary key
#  exception_time       :datetime         not null
#  availability_rule_id :integer          not null
#  created_at           :datetime         not null
#  updated_at           :datetime         not null
#
# Indexes
#
#  index_availability_rule_exceptions_on_availability_rule_id  (availability_rule_id)
#  index_availability_rule_exceptions_on_exception_time        (exception_time)
#

class AvailabilityRuleException < ApplicationRecord
  belongs_to :availability_rule

  validates_presence_of :exception_time
  validates_uniqueness_of :exception_time, scope: :availability_rule_id
end
