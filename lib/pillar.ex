defmodule Pillar do
  @moduledoc """
  """
  alias Pillar.Connection
  alias Pillar.HttpClient
  alias Pillar.QueryBuilder
  alias Pillar.ResponseParser

  def insert(%Connection{} = connection, query, params \\ %{}, options \\ %{}) do
    final_sql = QueryBuilder.build(query, params)
    timeout = Map.get(options, :timeout, 5_000)

    execute_sql(connection, final_sql, timeout)
  end

  def query(%Connection{} = connection, query, params \\ %{}, options \\ %{}) do
    final_sql = QueryBuilder.build(query, params)
    timeout = Map.get(options, :timeout, 5_000)

    execute_sql(connection, final_sql, timeout)
  end

  def select(%Connection{} = connection, query, params \\ %{}, options \\ %{}) do
    final_sql = QueryBuilder.build(query, params) <> "\n FORMAT JSON"
    timeout = Map.get(options, :timeout, 5_000)

    execute_sql(connection, final_sql, timeout)
  end

  defp execute_sql(connection, final_sql, timeout) do
    connection
    |> Connection.url_from_connection()
    |> HttpClient.post(final_sql, timeout: timeout)
    |> ResponseParser.parse()
  end

  defmacro __using__(
             connection_strings: connection_strings,
             name: name,
             pool_size: pool_size
           ) do
    quote do
      use GenServer
      import Supervisor.Spec

      @pool_timeout_for_waiting_worker 1_000

      defp poolboy_config do
        [
          name: {:local, unquote(name)},
          worker_module: Pillar.Pool.Worker,
          size: unquote(pool_size),
          max_overflow: Kernel.ceil(unquote(pool_size) * 0.3)
        ]
      end

      def start_link(_opts \\ nil) do
        children = [
          :poolboy.child_spec(:worker, poolboy_config(), unquote(connection_strings))
        ]

        opts = [strategy: :one_for_one, name: :"#{unquote(name)}.Supervisor"]
        Supervisor.start_link(children, opts)
      end

      def init(init_arg) do
        {:ok, init_arg}
      end

      def select(sql, params \\ %{}, options \\ %{}) do
        :poolboy.transaction(
          unquote(name),
          fn pid -> GenServer.call(pid, {:select, sql, params, options}, :infinity) end,
          @pool_timeout_for_waiting_worker
        )
      end

      def query(sql, params \\ %{}, options \\ %{}) do
        :poolboy.transaction(
          unquote(name),
          fn pid -> GenServer.call(pid, {:query, sql, params, options}, :infinity) end,
          @pool_timeout_for_waiting_worker
        )
      end

      def async_query(sql, params \\ %{}, options \\ %{}) do
        :poolboy.transaction(
          unquote(name),
          fn pid -> GenServer.cast(pid, {:query, sql, params, options}) end,
          @pool_timeout_for_waiting_worker
        )
      end

      def insert(sql, params \\ %{}, options \\ %{}) do
        :poolboy.transaction(
          unquote(name),
          fn pid -> GenServer.call(pid, {:insert, sql, params, options}, :infinity) end,
          @pool_timeout_for_waiting_worker
        )
      end

      def async_insert(sql, params \\ %{}, options \\ %{}) do
        :poolboy.transaction(
          unquote(name),
          fn pid -> GenServer.cast(pid, {:insert, sql, params, options}) end,
          @pool_timeout_for_waiting_worker
        )
      end
    end
  end
end
