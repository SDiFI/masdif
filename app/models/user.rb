class User < ApplicationRecord
  belongs_to :role
  before_create :set_default_role

  # Include default devise modules. Others available are:
  # :confirmable, :lockable, :timeoutable, :trackable and :omniauthable
  devise :database_authenticatable, 
         :recoverable, :rememberable, :validatable


  def admin?
    role.name == 'admin'
  end

  # Returns true if the user has the given role
  # @param [String, Symbol] role
  # @return [Boolean]
  def role?(role)
    self.role.name == role.to_s
  end

  private

  # Set the default role to user
  # @return [void]
  def set_default_role
    self.role ||= Role.find_by_name('user')
  end

end
