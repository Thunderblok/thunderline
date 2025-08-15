defmodule Thunderline.Support do
  @moduledoc """
  Support domain for helpdesk functionality.

  Following the official Ash getting started guide.
  """

  use Ash.Domain, extensions: [AshOban.Domain, AshGraphql.Domain]

  resources do
    resource Thunderline.Support.Ticket
  end

  graphql do
    queries do
      # Create a field called `get_ticket` that uses the `read` action to fetch a single ticket
      get Thunderline.Support.Ticket, :get_ticket, :read

      # Create a field called `list_tickets` that uses the `read` action to fetch a list of tickets
      list Thunderline.Support.Ticket, :list_tickets, :read
    end

    mutations do
      # Create a new ticket
      create Thunderline.Support.Ticket, :create_ticket, :open

      # Close an existing ticket
      update Thunderline.Support.Ticket, :close_ticket, :close

      # Process a ticket (manual trigger)
      update Thunderline.Support.Ticket, :process_ticket, :process

      # Escalate a ticket (manual trigger)
      update Thunderline.Support.Ticket, :escalate_ticket, :escalate
    end
  end
end
