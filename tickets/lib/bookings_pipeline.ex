defmodule BookingsPipeline do
  use Broadway

  def start_link(args) do
    rabbitmq_config = [
      queue: "bookings_queue",
      declare: [durable: true],
      on_failure: :reject_and_requeue
    ]

    opts = [
      name: __MODULE__,
      producer: [
        module: {BroadwayRabbitMQ.Producer, rabbitmq_config}
      ],
      processors: [
        default: []
      ],
      batchers: [
        cinema: [],
        musical: [],
        default: []
      ]
    ]

    Broadway.start_link(__MODULE__, opts)
  end

  def handle_message(_processor, message, _context) do
    %{data: %{event: event, user: user}} = message

    # TODO: check for tickets availability
    if (Tickets.tickets_available?(message.data.event)) do
      case message do
        %{data: %{event: "cinema"}} = message ->
          Broadway.Message.put_batcher(message, :cinema)

        %{data: %{event: "musical"}} = message ->
          Broadway.Message.put_batcher(message, :musical)

        message ->
          message
      end
    else
      Broadway.Message.failed(message, "bookings-closed")
    end
  end

  def handle_batch(_batcher, messages, batch_info, _context) do
    IO.puts("#{inspect(self())} Batch #{batch_info.batcher} #{batch_info.batch_key}")

    messages
    |> Tickets.insert_all_tickets()
    |> Enum.each(fn %{data: %{user: user}} ->
      Tickets.send_email(user)
    end)

    messages
  end

  def handle_failed(messages, _context) do
    IO.inspect(messages, label: "failed messages")

    Enum.map(messages, fn
      %{status: {:failed, "bookings-closed"}} = message ->
        Broadway.Message.configure_ack(message, on_failure: :reject)

      message ->
        message
    end)
  end

  def prepare_messages(messages, _context) do
    # Parse data and convert to a map.
    messages =
      Enum.map(messages, fn message ->
        Broadway.Message.update_data(message, fn data ->
          [event, user_id] = String.split(data, ",")
          %{event: event, user_id: user_id}
        end)
      end)

    users = Tickets.users_by_ids(Enum.map(messages, & &1.data.user_id))
    # Put users in messages.
    Enum.map(messages, fn message ->
      Broadway.Message.update_data(message, fn data ->
        user = Enum.find(users, &(&1.id == data.user_id))
        Map.put(data, :user, user)
      end)
    end)
  end
end
