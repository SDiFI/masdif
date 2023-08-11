ActiveAdmin.register User do

  permit_params do
    allowed_params = [:email, :password, :password_confirmation]
    allowed_params.push :role_id if authorized? :manage, User
    allowed_params
  end

  index do
    selectable_column
    id_column
    column :email
    column :role
    column :current_sign_in_at
    column :sign_in_count
    column :created_at
    actions
  end

  controller do
    def update
      model = :user
      # allow user to update a profile without entering a password, therefore
      # remove the password and password_confirmation fields if they are blank
      if params[model][:password].blank?
        %w(password password_confirmation).each { |p| params[model].delete(p) }
      end
      super
    end
  end

  filter :email
  filter :role
  filter :current_sign_in_at
  filter :sign_in_count
  filter :created_at

  form do |f|
    f.inputs do
      f.input :email
      f.input :password
      f.input :password_confirmation
      if authorized? :manage, User
        f.input :role, as: :select, collection: Role.all.map{|r| [r.name, r.id]}
      end
    end
    f.actions
  end

end
