require "test_helper"

class HiddenAssignmentTest < ActiveSupport::TestCase
  setup do
    @user = User.create!(
      email:         "ha_model@example.com",
      google_uid:    "uid_ha_#{SecureRandom.hex(4)}",
      access_token:  "tok",
      refresh_token: "ref"
    )
  end

  test "two records for the same user and course_work_id are not created" do
    HiddenAssignment.create!(user: @user, course_work_id: "cw1", hidden_at: Time.current)
    # find_or_create_by should not raise on duplicate
    ha2 = HiddenAssignment.find_or_create_by(user: @user, course_work_id: "cw1")
    assert_equal 1, HiddenAssignment.where(user: @user, course_work_id: "cw1").count
    assert_equal ha2, HiddenAssignment.find_by(user: @user, course_work_id: "cw1")
  end

  test "different users can hide the same assignment independently" do
    other = User.create!(
      email:         "ha_other@example.com",
      google_uid:    "uid_ha_other_#{SecureRandom.hex(4)}",
      access_token:  "tok",
      refresh_token: "ref"
    )
    HiddenAssignment.create!(user: @user,  course_work_id: "cw_shared", hidden_at: Time.current)
    HiddenAssignment.create!(user: other, course_work_id: "cw_shared", hidden_at: Time.current)
    assert_equal 2, HiddenAssignment.where(course_work_id: "cw_shared").count
  end
end
