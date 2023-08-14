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

  # Define the fields that can be searched by Ransack.
  # @note: for this model class make sure not to include any password fields.
  # @param [Object] auth_object
  # @return [Array<String>]
  def self.ransackable_attributes(auth_object = nil)
    ["created_at", "id", "email", "updated_at"]
  end

  # Define the associations that can be searched by Ransack
  # @param [Object] auth_object
  # @return [Array<String>]
  def self.ransackable_associations(auth_object = nil)
    ["role"]
  end

  private

  # Set the default role to user
  # @return [void]
  def set_default_role
    self.role ||= Role.find_by_name('user')
  end

end
