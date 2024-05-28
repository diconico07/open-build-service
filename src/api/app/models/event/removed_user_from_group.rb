module Event
  class RemovedUserFromGroup < Base
    self.message_bus_routing_key = 'groups_user.delete'
    self.description = 'Removed user from group'
    payload_keys :group, :user

    def subject
      "You've been removed from the group #{payload['group']}"
    end
  end
end
