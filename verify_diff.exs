decimal_path = System.get_env("DECIMAL_PATH", ".")
out = System.get_env("OUT") || raise "set OUT=<file>"

Mix.install([{:decimal, path: decimal_path, override: true}])

# Dumps the observable behaviour of the whole public surface - results, struct
# representations, raised errors and context flags - over a deterministic case
# matrix. Run it against two builds and diff the output: any behaviour change
# shows up as a diff line.
#
#   OUT=/tmp/a DECIMAL_PATH=/tmp/decimal-baseline MIX_ENV=prod elixir verify_diff.exs
#   OUT=/tmp/b MIX_ENV=prod elixir verify_diff.exs
#   diff /tmp/a /tmp/b

# `Decimal` is only available at runtime under Mix.install, so build structs
# through constructors instead of struct literals.
ctx = fn fields -> struct(Decimal.Context, fields) end
default_ctx = ctx.([])

coefs = [
  0,
  1,
  2,
  5,
  9,
  10,
  11,
  50,
  99,
  100,
  999,
  1_000,
  12_345,
  999_999_999,
  1_000_000_000,
  99_999_999_999_999_999,
  100_000_000_000_000_000,
  999_999_999_999_999_999,
  1_000_000_000_000_000_000,
  1_000_000_000_000_000_001,
  1_234_567_890_123_456_789_012_345_678_901_234,
  9_999_999_999_999_999_999_999_999_999_999_999,
  10_000_000_000_000_000_000_000_000_000_000_000,
  12_345_678_901_234_567_890_123_456_789_012_345_678_901_234,
  :NaN,
  :inf
]

exps = [-6200, -320, -300, -40, -35, -34, -20, -7, -6, -2, -1, 0, 1, 2, 6, 7, 20, 34, 300, 6200]

decimals =
  for sign <- [1, -1], coef <- coefs, exp <- exps do
    Decimal.new(sign, coef, exp)
  end

# every 23rd decimal keeps the pair matrix at a few thousand cases
pair_sample = Enum.take_every(decimals, 23)
pairs = for a <- pair_sample, b <- pair_sample, do: {a, b}

raw = fn d -> if is_struct(d, Decimal), do: {d.sign, d.coef, d.exp}, else: d end

# Each case runs in a pristine context so the flags reported belong to it.
run = fn fun ->
  Decimal.Context.with(default_ctx, fn ->
    result =
      try do
        {:ok, fun.()}
      rescue
        e -> {:raised, e.__struct__, Exception.message(e)}
      end

    {result, Decimal.Context.get().flags}
  end)
end

format = fn
  {{:ok, {a, b}}, flags} when is_struct(a, Decimal) and is_struct(b, Decimal) ->
    "#{inspect({raw.(a), raw.(b)})} #{inspect(flags)}"

  {{:ok, value}, flags} ->
    "#{inspect(raw.(value))} #{inspect(flags)}"

  {{:raised, mod, msg}, flags} ->
    "raise #{inspect(mod)} #{inspect(msg)} #{inspect(flags)}"
end

file = File.open!(out, [:write, :raw, :delayed_write])
emit = fn label, fun -> IO.binwrite(file, [label, " => ", format.(run.(fun)), "\n"]) end

for {a, b} <- pairs do
  key = "#{inspect(raw.(a))} #{inspect(raw.(b))}"
  emit.("add #{key}", fn -> Decimal.add(a, b) end)
  emit.("sub #{key}", fn -> Decimal.sub(a, b) end)
  emit.("mult #{key}", fn -> Decimal.mult(a, b) end)
  emit.("div #{key}", fn -> Decimal.div(a, b) end)
  emit.("div_int #{key}", fn -> Decimal.div_int(a, b) end)
  emit.("rem #{key}", fn -> Decimal.rem(a, b) end)
  emit.("div_rem #{key}", fn -> Decimal.div_rem(a, b) end)
  emit.("compare #{key}", fn -> Decimal.compare(a, b) end)
  emit.("equal? #{key}", fn -> Decimal.equal?(a, b) end)
  emit.("max #{key}", fn -> Decimal.max(a, b) end)
  emit.("min #{key}", fn -> Decimal.min(a, b) end)
end

for d <- decimals do
  key = inspect(raw.(d))
  emit.("normalize #{key}", fn -> Decimal.normalize(d) end)
  emit.("abs #{key}", fn -> Decimal.abs(d) end)
  emit.("negate #{key}", fn -> Decimal.negate(d) end)
  emit.("apply_context #{key}", fn -> Decimal.apply_context(d) end)
  emit.("sqrt #{key}", fn -> Decimal.sqrt(d) end)
  emit.("integer? #{key}", fn -> Decimal.integer?(d) end)
  emit.("scale #{key}", fn -> Decimal.scale(d) end)
  emit.("positive? #{key}", fn -> Decimal.positive?(d) end)
  emit.("negative? #{key}", fn -> Decimal.negative?(d) end)
  emit.("to_integer #{key}", fn -> Decimal.to_integer(d) end)
  emit.("to_float #{key}", fn -> Decimal.to_float(d) end)
  emit.("inspect #{key}", fn -> inspect(d) end)

  for type <- [:scientific, :normal, :xsd, :raw] do
    emit.("to_string #{type} #{key}", fn -> Decimal.to_string(d, type) end)
  end

  for places <- [-40, -3, 0, 1, 2, 7, 40],
      mode <- [:down, :half_up, :half_even, :ceiling, :floor, :half_down, :up] do
    emit.("round #{places} #{mode} #{key}", fn -> Decimal.round(d, places, mode) end)
  end
end

# rounding and precision behaviour under non-default contexts
for precision <- [1, 2, 5, 7, 34],
    rounding <- [:down, :half_up, :half_even, :ceiling, :floor, :half_down, :up],
    {a, b} <- Enum.take_every(pairs, 97) do
  case_ctx = ctx.(precision: precision, rounding: rounding)
  key = "#{precision} #{rounding} #{inspect(raw.(a))} #{inspect(raw.(b))}"

  emit.("ctx add #{key}", fn -> Decimal.Context.with(case_ctx, fn -> Decimal.add(a, b) end) end)
  emit.("ctx mult #{key}", fn -> Decimal.Context.with(case_ctx, fn -> Decimal.mult(a, b) end) end)
  emit.("ctx div #{key}", fn -> Decimal.Context.with(case_ctx, fn -> Decimal.div(a, b) end) end)
  emit.("ctx sqrt #{key}", fn -> Decimal.Context.with(case_ctx, fn -> Decimal.sqrt(a) end) end)
end

for emax <- [:infinity, 6144, 20, 2], emin <- [:infinity, -6143, -20, -2] do
  case_ctx = ctx.(emax: emax, emin: emin, traps: [])

  for {a, b} <- Enum.take_every(pairs, 211) do
    key = "#{inspect(emax)} #{inspect(emin)} #{inspect(raw.(a))} #{inspect(raw.(b))}"
    emit.("lim add #{key}", fn -> Decimal.Context.with(case_ctx, fn -> Decimal.add(a, b) end) end)
    emit.("lim mult #{key}", fn -> Decimal.Context.with(case_ctx, fn -> Decimal.mult(a, b) end) end)
    emit.("lim div #{key}", fn -> Decimal.Context.with(case_ctx, fn -> Decimal.div(a, b) end) end)
  end
end

strings = [
  "0",
  "-0",
  "0.0",
  "3.14",
  "-3.14",
  "+3.14",
  ".5",
  "5.",
  "1e10",
  "1E-10",
  "1e+10",
  "-1.1e3",
  "0.0000000001",
  "1234567890123456789012345678901234",
  "12345678901234567890123456789012345",
  "0.000000000000000000000000000000000000001",
  "1e6144",
  "1e6145",
  "1e-6143",
  "1e-6200",
  "00000000000000000000000000000000000000001.5",
  "inf",
  "Infinity",
  "-inf",
  "nan",
  "NaN",
  "-NaN",
  "bad",
  "1.2.3",
  "1e",
  "1e+",
  "",
  "1_000"
]

for s <- strings do
  emit.("parse #{inspect(s)}", fn -> Decimal.parse(s) end)
  emit.("new #{inspect(s)}", fn -> Decimal.new(s) end)
  emit.("cast #{inspect(s)}", fn -> Decimal.cast(s) end)

  for opts <- [[], [max_digits: 5], [max_digits: :infinity], [max_exponent: 10], [max_exponent: :infinity]] do
    emit.("parse2 #{inspect(s)} #{inspect(opts)}", fn -> Decimal.parse(s, opts) end)
    emit.("cast2 #{inspect(s)} #{inspect(opts)}", fn -> Decimal.cast(s, opts) end)
  end
end

# Flags are sticky and accumulate across operations, so run sequences of
# operations inside one context and record the flags after every step. A
# single-operation-per-context check would never exercise re-signalling.
for {label, ops} <- [
      {"inexact chain",
       [
         {:div, "1", "3"},
         {:div, "1", "3"},
         {:add, "1", "0.0000000000000000000000000000000000001"},
         {:mult, "1.5", "2"},
         {:div, "10", "2"},
         {:div, "2", "7"},
         {:sqrt, "2", nil},
         {:add, "1", "2"}
       ]},
      {"overflow chain",
       [
         {:mult, "1e6000", "1e6000"},
         {:add, "1", "2"},
         {:mult, "1e-6000", "1e-6000"},
         {:div, "1", "3"},
         {:mult, "1e6000", "1e6000"}
       ]},
      {"clean chain", [{:add, "1", "2"}, {:mult, "3", "4"}, {:sub, "5", "6"}, {:div, "8", "2"}]}
    ] do
  emit.("flag sequence #{label}", fn ->
    Decimal.Context.with(ctx.(traps: []), fn ->
      Enum.map(ops, fn
        {:sqrt, a, _} ->
          result = Decimal.sqrt(a)
          {Decimal.to_string(result, :raw), Decimal.Context.get().flags}

        {op, a, b} ->
          result = apply(Decimal, op, [a, b])
          {Decimal.to_string(result, :raw), Decimal.Context.get().flags}
      end)
    end)
  end)
end

# The same sequences with traps enabled, so a trapped signal raises mid-chain
for signal <- [:inexact, :rounded, :overflow, :underflow] do
  emit.("trap #{signal}", fn ->
    Decimal.Context.with(ctx.(traps: [signal]), fn ->
      Enum.map([{:div, "1", "3"}, {:mult, "1e6000", "1e6000"}, {:add, "1", "2"}], fn {op, a, b} ->
        try do
          {Decimal.to_string(apply(Decimal, op, [a, b]), :raw), Decimal.Context.get().flags}
        rescue
          e -> {:raised, Exception.message(e), Decimal.Context.get().flags}
        end
      end)
    end)
  end)
end

# Deterministic fuzz over the parser: digits, dots, signs, exponents with
# leading zeros and huge magnitudes, garbage prefixes and suffixes.
:rand.seed(:exsss, {17, 42, 4711})

digits = fn n -> for _ <- 1..n, into: "", do: <<Enum.random(?0..?9)>> end

fuzz_strings =
  for _ <- 1..4000 do
    int_len = Enum.random(0..40)
    frac_len = Enum.random(0..40)
    zeros = String.duplicate("0", Enum.random(0..8))

    int = if int_len == 0, do: "", else: zeros <> digits.(int_len)
    frac = if frac_len == 0, do: "", else: digits.(frac_len)

    # a trailing point with no fraction digits is valid input too
    dot =
      cond do
        frac != "" -> "."
        Enum.random(1..4) == 1 -> "."
        true -> ""
      end

    exp =
      case Enum.random(1..8) do
        1 -> ""
        2 -> "e" <> digits.(Enum.random(1..3))
        3 -> "E-" <> digits.(Enum.random(1..3))
        4 -> "e+" <> digits.(Enum.random(1..5))
        5 -> "e" <> String.duplicate("0", Enum.random(1..10)) <> digits.(Enum.random(1..4))
        6 -> "e-" <> digits.(Enum.random(6..25))
        7 -> "e"
        8 -> "E+"
      end

    sign = Enum.random(["", "-", "+"])
    tail = Enum.random(["", "x", ".5", "e3", " ", "-"])

    sign <> int <> dot <> frac <> exp <> tail
  end

fuzz_limits = [
  [],
  [max_digits: 0],
  [max_digits: 1],
  [max_digits: 5],
  [max_digits: 34],
  [max_digits: :infinity],
  [max_exponent: 0],
  [max_exponent: 1],
  [max_exponent: 10],
  [max_exponent: 6144],
  [max_exponent: :infinity],
  [max_digits: :infinity, max_exponent: :infinity]
]

for s <- fuzz_strings do
  emit.("fuzz parse #{inspect(s)}", fn -> Decimal.parse(s) end)

  opts = Enum.random(fuzz_limits)
  emit.("fuzz parse2 #{inspect(s)} #{inspect(opts)}", fn -> Decimal.parse(s, opts) end)
  emit.("fuzz cast #{inspect(s)} #{inspect(opts)}", fn -> Decimal.cast(s, opts) end)
end

for s <- Enum.take(fuzz_strings, 400), opts <- fuzz_limits do
  emit.("fuzz grid #{inspect(s)} #{inspect(opts)}", fn -> Decimal.parse(s, opts) end)
end

floats = [
  0.0,
  -0.0,
  1.0,
  1.5,
  -1.5,
  0.1,
  3.14,
  100_000.0,
  1.0e-5,
  1.0e-300,
  1.0e300,
  2.2250738585072014e-308,
  1.7976931348623157e308,
  123_456_789.123456,
  1.0e16,
  1.0e17
]

for f <- floats do
  emit.("from_float #{inspect(f)}", fn -> Decimal.from_float(f) end)
  emit.("cast_float #{inspect(f)}", fn -> Decimal.cast(f) end)
  emit.("roundtrip #{inspect(f)}", fn -> f |> Decimal.from_float() |> Decimal.to_float() end)
end

# `from_float/1` reformats the rendered float, so sweep the shapes that
# rendering can take: every power of ten, integral values, subnormals, and a
# large random sample across the exponent range.
# products that overflow the double range raise, so keep only what survives
finite = fn thunk ->
  try do
    [thunk.()]
  rescue
    _ -> []
  end
end

float_fuzz =
  Enum.flat_map(-323..308, fn e ->
    base = :math.pow(10.0, e)

    Enum.flat_map(
      [
        fn -> base end,
        fn -> base * 1.5 end,
        fn -> base * 9.87654321 end,
        fn -> -base end,
        fn -> base * 2.0 end,
        fn -> base * 1.0000000000000002 end
      ],
      finite
    )
  end) ++
    Enum.map(1..40, &(&1 * 1.0)) ++
    Enum.map(1..40, &(1.0 / &1)) ++
    [5.0e-324, 1.0e-323, 2.2250738585072011e-308, 1.7976931348623157e308] ++
    Enum.flat_map(1..6000, fn i ->
      finite.(fn -> :rand.uniform() * :math.pow(10.0, rem(i * 7, 600) - 300) end)
    end)

for f <- float_fuzz do
  emit.("float fuzz from #{inspect(f)}", fn -> Decimal.from_float(f) end)
  emit.("float fuzz raw #{inspect(f)}", fn -> Decimal.to_string(Decimal.from_float(f), :raw) end)
  emit.("float fuzz trip #{inspect(f)}", fn -> f |> Decimal.from_float() |> Decimal.to_float() end)
end

for i <- [0, 1, -1, 42, -42, 10_000_000_000_000_000_000, -10_000_000_000_000_000_000] do
  emit.("new_int #{i}", fn -> Decimal.new(i) end)
  emit.("cast_int #{i}", fn -> Decimal.cast(i) end)
  emit.("to_float_int #{i}", fn -> i |> Decimal.new() |> Decimal.to_float() end)
end

# every to_float that a double can represent, across the whole exponent range
for exp <- -330..310, coef <- [1, 15, 1234567890123456, 9999999999999999] do
  emit.("to_float_sweep #{coef} #{exp}", fn -> Decimal.to_float(Decimal.new(1, coef, exp)) end)
  emit.("to_float_sweep- #{coef} #{exp}", fn -> Decimal.to_float(Decimal.new(-1, coef, exp)) end)
end

File.close(file)
IO.puts("wrote #{out}")
