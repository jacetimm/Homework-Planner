class HiddenAssignment < ApplicationRecord
  belongs_to :user
  
  validates :course_work_id, presence: true, uniqueness: { scope: :user_id }
end
