class CreateRoles < ActiveRecord::Migration[7.0]
  def change
    create_table :roles, id: :uuid do |t|
      t.string :name

      t.timestamps
    end

    # prepopulate roles
    %w[user admin].each do |role|
      Role.create(name: role)
    end
  end
end
