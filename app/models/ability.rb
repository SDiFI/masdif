# frozen_string_literal: true

class Ability
  include CanCan::Ability

  def initialize(user)
    # See the wiki for details:
    # https://github.com/CanCanCommunity/cancancan/blob/develop/docs/define_check_abilities.md

    return unless user.present?

    if user.role? :user
      can :read, ActiveAdmin::Page, name: "Dashboard", namespace_name: "admin"
      can :read, Conversation
      can :read, Message
      can :read, User
      can :update, User, id: user.id
    elsif user.admin?
      can :manage, :all
      # admin can't delete himself. This guaranties that there is at least one admin left
      cannot :destroy, User, id: user.id
    end
  end
end
