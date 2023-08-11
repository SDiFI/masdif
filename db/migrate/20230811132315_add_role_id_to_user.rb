class AddRoleIdToUser < ActiveRecord::Migration[7.0]
  def change
    add_reference :users, :role, null: true, foreign_key: true, type: :uuid

    # Change existing users to have the admin role (that is what they are)
    User.all.each do |user|
      user.role = Role.find_by_name('admin')
      user.save!
    end
  end
end
