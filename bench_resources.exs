Code.require_file("bench_helper.exs", __DIR__)

# Benchmarks must measure production-compiled code:
#
#     MIX_ENV=prod elixir bench_resources.exs
#
# To compare two builds, save one run and compare the next against it. The
# saved file holds the measurements themselves, so nothing has to parse the
# printed table back:
#
#     DECIMAL_PATH=../decimal-main SAVE=/tmp/main.bench MIX_ENV=prod \
#       elixir bench_resources.exs
#     COMPARE=/tmp/main.bench MIX_ENV=prod elixir bench_resources.exs
#
BenchHelper.install!()

defmodule Resources do
  @moduledoc """
  Resource accounting for a workload, measured in a dedicated process.

  Wall time alone is not a verdict: an implementation that is faster but burns
  more CPU or allocates more is usually a bad trade. So every workload reports

    * `wall/op`   - wall clock per operation
    * `cpu/op`    - VM CPU time per operation, summed over *all* schedulers
                    (a wall-time win paid for with extra CPU shows up here)
    * `reds/op`   - reductions per operation: deterministic work units, immune
                    to machine noise
    * `alloc/op`  - heap words allocated per operation (allocation churn)
    * `copy/op`   - heap words copied by the collector per operation. This is
                    the GC's actual cost, and it is the metric that punishes
                    allocating many small objects when they are *not* garbage
                    by the time the collector runs
    * `gc/1k`     - collections per 1k operations, minor + major
    * `peak KB`   - peak process footprint during the run (the memory spike)

  Every workload is measured twice:

    * `discard` - results are dropped immediately. Garbage dies young, minor
      collections are cheap, and allocation looks almost free. This is what a
      throwaway benchmark process measures.
    * `retain`  - a live set is held across the whole run and every result is
      kept in a list. Now each collection has to trace and copy live data, and
      produced terms get promoted to the old heap, so the true cost of
      producing many objects is visible.
  """

  def measure(fun, reps, mode, live_set) do
    parent = self()

    pid =
      spawn(fn ->
        # `live_set` is referenced after the loop so it stays live for the
        # whole run and has to be traced by every collection.
        receive do: (:go -> :ok)
        acc = loop(fun, reps, mode, [])
        send(parent, {:done, self()})
        # The hash keeps `acc` and the live set referenced past the loop. It
        # runs only after the parent has taken every measurement, so its cost
        # lands in none of them.
        receive do: (:measured -> :ok)
        send(parent, {:hash, self(), :erlang.phash2({acc, live_set})})
        receive do: (:stop -> :ok)
      end)

    :erlang.trace(pid, true, [:garbage_collection])
    info0 = Process.info(pid, [:reductions, :garbage_collection_info])
    sched0 = scheduler_active()
    t0 = System.monotonic_time(:nanosecond)
    send(pid, :go)

    receive do
      {:done, ^pid} -> :ok
    end

    t1 = System.monotonic_time(:nanosecond)
    sched1 = scheduler_active()
    :erlang.trace(pid, false, [:garbage_collection])
    info = Process.info(pid, [:reductions, :garbage_collection_info])
    send(pid, :measured)

    receive do
      {:hash, ^pid, _hash} -> :ok
    end

    send(pid, :stop)

    events = drain([])
    gc = summarize(events, info, used_words(info0[:garbage_collection_info] || []))

    %{
      wall_ns: (t1 - t0) / reps,
      cpu_ns: (sched1 - sched0) / reps,
      reds: (info[:reductions] - info0[:reductions]) / reps,
      alloc_w: gc.allocated / reps,
      copy_w: gc.copied / reps,
      minor: gc.minor * 1000 / reps,
      major: gc.major * 1000 / reps,
      peak_kb: gc.peak_words * 8 / 1024
    }
  end

  defp loop(_fun, 0, _mode, acc), do: acc

  defp loop(fun, n, :discard, acc) do
    fun.()
    loop(fun, n - 1, :discard, acc)
  end

  defp loop(fun, n, :retain, acc) do
    loop(fun, n - 1, :retain, [fun.() | acc])
  end

  # Sum of active time over all schedulers, normal and dirty: the VM's total
  # CPU consumption, not just the wall time of one process.
  defp scheduler_active do
    :erlang.statistics(:scheduler_wall_time)
    |> Enum.reduce(0, fn {_id, active, _total}, sum -> sum + active end)
  end

  defp drain(acc) do
    receive do
      {:trace, _pid, event, info} -> drain([{event, info} | acc])
    after
      0 -> :lists.reverse(acc)
    end
  end

  # Allocation is the growth of the used heap between the end of one collection
  # and the start of the next, on top of the heap the process was spawned with.
  # Copying is what a collection moves: a minor collection copies the surviving
  # young heap plus what it promotes and leaves the rest of the old heap where
  # it is, while a major collection rebuilds the whole live set.
  defp summarize(events, info, spawned_words) do
    init = %{
      allocated: 0,
      copied: 0,
      last_end: spawned_words,
      old_at_start: 0,
      peak_words: 0,
      minor: 0,
      major: 0
    }

    acc =
      Enum.reduce(events, init, fn {event, gc}, acc ->
        used = used_words(gc)

        case event do
          :gc_minor_start ->
            %{
              acc
              | allocated: acc.allocated + max(used - acc.last_end, 0),
                old_at_start: Keyword.get(gc, :old_heap_size, 0),
                peak_words: max(acc.peak_words, held(gc)),
                minor: acc.minor + 1
            }

          :gc_major_start ->
            %{
              acc
              | allocated: acc.allocated + max(used - acc.last_end, 0),
                old_at_start: Keyword.get(gc, :old_heap_size, 0),
                peak_words: max(acc.peak_words, held(gc)),
                major: acc.major + 1
            }

          :gc_minor_end ->
            copied =
              Keyword.get(gc, :heap_size, 0) +
                (Keyword.get(gc, :old_heap_size, 0) - acc.old_at_start)

            %{acc | copied: acc.copied + max(copied, 0), last_end: used}

          :gc_major_end ->
            %{acc | copied: acc.copied + used, last_end: used}

          _ ->
            acc
        end
      end)

    final = info[:garbage_collection_info] || []

    %{
      acc
      | allocated: acc.allocated + max(used_words(final) - acc.last_end, 0),
        peak_words: max(acc.peak_words, held(final))
    }
  end

  defp used_words(gc) do
    Keyword.get(gc, :heap_size, 0) + Keyword.get(gc, :old_heap_size, 0)
  end

  defp held(gc) do
    Keyword.get(gc, :heap_block_size, 0) + Keyword.get(gc, :old_heap_block_size, 0) +
      Keyword.get(gc, :mbuf_size, 0) + Keyword.get(gc, :stack_size, 0)
  end

  # Reported in this order, each as `{label, key, precision}`.
  @metrics [
    {"wall/op", :wall_ns, 1},
    {"cpu/op", :cpu_ns, 1},
    {"reds/op", :reds, 1},
    {"alloc/op", :alloc_w, 1},
    {"copy/op", :copy_w, 1},
    {"minor/1k", :minor, 2},
    {"major/1k", :major, 2},
    {"peak KB", :peak_kb, 1}
  ]

  @name_width 18
  @mode_width 8
  @value_width 10
  @delta_width 6

  def header(comparing?) do
    width = if comparing?, do: @value_width + @delta_width, else: @value_width

    @metrics
    |> Enum.map(fn {label, _key, _precision} -> String.pad_leading(label, width) end)
    |> emit_row("operation", "mode")
  end

  # `baseline` is the matching measurement from the run being compared against,
  # or nil when this workload was not in it.
  def row(name, mode, measurement, baseline, comparing?) do
    @metrics
    |> Enum.map(&cell(&1, measurement, baseline, comparing?))
    |> emit_row(name, Atom.to_string(mode))
  end

  defp emit_row(cells, name, mode) do
    name = String.pad_trailing(name, @name_width)
    mode = String.pad_trailing(mode, @mode_width)
    IO.puts(Enum.join([name, mode | cells], " "))
  end

  defp cell({_label, key, precision}, measurement, baseline, comparing?) do
    value = Map.fetch!(measurement, key)
    formatted = value |> :erlang.float_to_binary(decimals: precision) |> pad(@value_width)

    cond do
      not comparing? -> formatted
      baseline == nil -> formatted <> pad("new", @delta_width)
      true -> formatted <> delta(value, Map.fetch!(baseline, key))
    end
  end

  # A percentage against a zero baseline says nothing.
  defp delta(_value, baseline) when baseline == 0, do: pad("-", @delta_width)

  defp delta(value, baseline) do
    percent = (value - baseline) / baseline * 100
    sign = if percent < 0, do: "-", else: "+"
    pad("#{sign}#{:erlang.float_to_binary(abs(percent), decimals: 0)}%", @delta_width)
  end

  defp pad(string, width), do: String.pad_leading(string, width)

  # A workload runs `count` operations per repetition, so everything except the
  # peak footprint - which belongs to the process, not to one operation - is
  # divided down to a single operation.
  @per_operation [:wall_ns, :cpu_ns, :reds, :alloc_w, :copy_w, :minor, :major]

  def per_operation(measurement, count) do
    Enum.reduce(@per_operation, measurement, fn key, acc ->
      Map.update!(acc, key, &(&1 / count))
    end)
  end

  def load(nil), do: %{}

  def load(path) do
    measurements = path |> File.read!() |> :erlang.binary_to_term()
    keys = Enum.map(@metrics, fn {_label, key, _precision} -> key end)

    valid? =
      is_map(measurements) and
        Enum.all?(Map.values(measurements), fn measurement ->
          is_map(measurement) and Enum.all?(keys, &Map.has_key?(measurement, &1))
        end)

    if valid? do
      measurements
    else
      raise "#{path} does not hold measurements for #{inspect(keys)}; re-save it with SAVE="
    end
  end

  def save(nil, _rows), do: :ok

  def save(path, rows) do
    File.write!(path, :erlang.term_to_binary(rows))
    IO.puts("\nsaved #{map_size(rows)} measurements to #{path}")
  end
end

## Workloads ##################################################################

:erlang.system_flag(:scheduler_wall_time, true)

money_strings = BenchHelper.money_strings()
money = Enum.map(money_strings, &Decimal.new/1)
money_pairs = Enum.zip(money, Enum.reverse(money))

wide =
  Enum.map(1..50, fn i ->
    Decimal.new(1, 1_234_567_890_123_456_789_012_345_678_901_234 + i, -6 + rem(i, 5))
  end)

wide_pairs = Enum.zip(wide, Enum.reverse(wide))
tiny = Enum.map(1..50, &Decimal.new("#{&1}e-300"))
floats = Enum.map(1..200, &(&1 * 1.37))

# A live set the workload process holds for its entire lifetime, so the
# collector has real work to do on every pass, the way it does in a long-lived
# process that owns state.
live_set = Enum.map(1..20_000, &Decimal.new(1, &1 * 7919, -2))

pairs = fn list, fun -> fn -> Enum.map(list, fn {a, b} -> fun.(a, b) end) end end
over = fn list, fun -> fn -> Enum.map(list, fun) end end

workloads = [
  {"add money", pairs.(money_pairs, &Decimal.add/2), 150, 200},
  {"sub money", pairs.(money_pairs, &Decimal.sub/2), 150, 200},
  {"mult money", pairs.(money_pairs, &Decimal.mult/2), 150, 200},
  {"div money", pairs.(money_pairs, &Decimal.div/2), 60, 200},
  {"compare money", pairs.(money_pairs, &Decimal.compare/2), 300, 200},
  {"round money 2", over.(money, &Decimal.round(&1, 2)), 150, 200},
  {"normalize money", over.(money, &Decimal.normalize/1), 300, 200},
  {"new money string", over.(money_strings, &Decimal.new/1), 150, 200},
  {"to_string money", over.(money, &Decimal.to_string/1), 150, 200},
  {"to_float money", over.(money, &Decimal.to_float/1), 60, 200},
  {"from_float", over.(floats, &Decimal.from_float/1), 60, 200},
  {"add wide", pairs.(wide_pairs, &Decimal.add/2), 300, 50},
  {"mult wide", pairs.(wide_pairs, &Decimal.mult/2), 300, 50},
  {"div wide", pairs.(wide_pairs, &Decimal.div/2), 150, 50},
  {"sqrt wide", over.(wide, &Decimal.sqrt/1), 60, 50},
  {"to_float tiny", over.(tiny, &Decimal.to_float/1), 15, 50}
]

compare_to = System.get_env("COMPARE")
baseline = Resources.load(compare_to)
save_to = System.get_env("SAVE")
rounds = String.to_integer(System.get_env("ROUNDS", "3"))

IO.puts("Decimal beam: #{:code.which(Decimal)}")
IO.puts("live set: #{length(live_set)} decimals held across every run")
if compare_to, do: IO.puts("comparing against #{compare_to}")
IO.puts("")

Resources.header(compare_to != nil)

rows =
  for {name, fun, reps, per_rep} <- workloads, mode <- [:discard, :retain], into: %{} do
    # one untimed pass so the JIT has compiled everything
    Resources.measure(fun, max(div(reps, 10), 1), mode, live_set)

    # Wall and CPU time are noisy on a shared machine while reductions and
    # allocation are deterministic, so take the fastest of several runs: the
    # minimum is the estimate least polluted by unrelated system activity.
    measurement =
      Enum.map(1..rounds, fn _ -> Resources.measure(fun, reps, mode, live_set) end)
      |> Enum.min_by(& &1.wall_ns)
      |> Resources.per_operation(per_rep)

    Resources.row(name, mode, measurement, baseline[{name, mode}], compare_to != nil)

    {{name, mode}, measurement}
  end

Resources.save(save_to, rows)
