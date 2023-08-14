class ApplicationRecord < ActiveRecord::Base
  primary_abstract_class

  # Sort records by date of creation instead of primary key
  self.implicit_order_column = :created_at

  # Define the fields that can be searched by Ransack
  # @param [Object] auth_object
  # @return [Array<String>]
  def self.ransackable_attributes(auth_object = nil)
    authorizable_ransackable_attributes
  end

  # Define the associations that can be searched by Ransack
  # @param [Object] auth_object
  # @return [Array<String>]
  def self.ransackable_associations(auth_object = nil)
    authorizable_ransackable_associations
  end
end
