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
      ]
    ]

    Broadway.start_link(__MODULE__, opts)
  end
end
