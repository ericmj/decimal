Code.require_file("bench_helper.exs", __DIR__)

# Measure production-compiled code:
#
#     MIX_ENV=prod elixir bench.exs
#
# To compare two checkouts, measure one and load its results into the run of
# the other, which makes Benchee print both per job:
#
#     DECIMAL_PATH=../decimal-main MIX_ENV=prod elixir bench.exs
#     LOAD=benchmarks/HEAD-0c0f72c.benchee MIX_ENV=prod elixir bench.exs
#
decimal_path = BenchHelper.install!([{:benchee, "~> 1.0"}, {:benchee_html, "~> 1.0"}])

# The tag names the code under test, which is not necessarily this checkout.
# `--abbrev-ref` reports `HEAD` rather than failing when that checkout has no
# branch, as a worktree at a bare commit does.
{head, 0} = System.cmd("git", ["-C", decimal_path, "rev-parse", "--abbrev-ref", "HEAD"])
{hash, 0} = System.cmd("git", ["-C", decimal_path, "rev-parse", "--short", "HEAD"])

tag = "#{String.trim(head)}-#{String.trim(hash)}"

numbers = "12345678901234567890"
coef_base_10s = Enum.scan(1..20, fn _elem, acc -> acc * 10 end)
coef_repeated = Enum.map(1..20, &(numbers |> String.slice(1..&1) |> String.to_integer()))
coefs = coef_base_10s ++ coef_repeated
exps = -20..20
signs = [1, -1]

decimals =
  for sign <- signs,
      coef <- coefs,
      exp <- exps,
      do: struct(Decimal, %{sign: sign, coef: coef, exp: exp})

decimal_pairs = for first <- decimals, second <- decimals, do: {first, second}

# The full pair matrix (~10.7M pairs) is kept for `compare` so results stay
# comparable with previously saved benchmarks. For the more expensive
# arithmetic operations a deterministic sample keeps each benchee iteration
# short enough to gather useful statistics.
sampled_pairs = Enum.take_every(decimal_pairs, 199)

positive_decimals = Enum.filter(decimals, &(&1.sign == 1))

# `round/3` is invalid for a result wider than the default precision of 34
# digits, so it only gets the decimals whose two-decimal result fits.
round_decimals = Enum.filter(decimals, &(&1.exp + length(Integer.digits(&1.coef)) + 2 <= 34))

# High-precision operands at the decimal128 default precision (34 digits),
# where division and rounding costs dominate.
high_precision_coefs = [
  1_234_567_890_123_456_789_012_345_678_901_234,
  4_321_098_765_432_109_876_543_210_987_654_321,
  9_999_999_999_999_999_999_999_999_999_999_999,
  1_000_000_000_000_000_000_000_000_000_000_000
]

high_precision_decimals =
  for coef <- high_precision_coefs,
      exp <- [-40, -6, 0, 6, 40],
      do: struct(Decimal, %{sign: 1, coef: coef, exp: exp})

high_precision_pairs =
  for first <- high_precision_decimals,
      second <- high_precision_decimals,
      do: {first, second}

# Pairs with equal exponents and equal-length coefficients never short-circuit
# on the adjusted exponent, so every comparison reaches the coefficient
# alignment. This is the typical shape of same-scale comparisons, e.g. money
# amounts at a fixed scale.
same_scale_base = 1_234_567_890_123_456

same_scale_decimals =
  Enum.map(0..99, &struct(Decimal, %{sign: 1, coef: same_scale_base + &1, exp: -2}))

same_scale_pairs =
  for first <- same_scale_decimals,
      second <- same_scale_decimals,
      do: {first, second}

each_pair = fn pairs, fun ->
  fn -> Enum.each(pairs, fn {first, second} -> fun.(first, second) end) end
end

each = fn decimals, fun ->
  fn -> Enum.each(decimals, fun) end
end

money_strings = BenchHelper.money_strings()
money = Enum.map(money_strings, &Decimal.new/1)
money_pairs = Enum.zip(money, Enum.reverse(money))
money_threshold = Decimal.new("0.01")

# Whole amounts at the money scale, which `to_integer/1` converts by dropping
# the zero cents, and the integers they come from.
integers = Enum.map(1..200, &(&1 * 37_123))
whole_money = Enum.map(integers, &Decimal.new(1, &1 * 100, -2))

context = struct(Decimal.Context, precision: 10)

floats = for i <- 1..200, do: i * 1.37

# Conversions to float scale the operand into the significand of a double, so
# operands near the ends of the exponent range do the most work. Exponents stay
# inside the double range, which `to_float/1` requires.
float_range_decimals =
  for coef <- [1, 15, 1_234_567_890_123_456], exp <- [-290, -30, -1, 0, 1, 30, 290] do
    struct(Decimal, %{sign: 1, coef: coef, exp: exp})
  end

jobs = %{
  "compare" => each_pair.(decimal_pairs, &Decimal.compare/2),
  "compare same scale" => each_pair.(same_scale_pairs, &Decimal.compare/2),
  "add" => each_pair.(sampled_pairs, &Decimal.add/2),
  "sub" => each_pair.(sampled_pairs, &Decimal.sub/2),
  "mult" => each_pair.(sampled_pairs, &Decimal.mult/2),
  "div" => each_pair.(sampled_pairs, &Decimal.div/2),
  "add high precision" => each_pair.(high_precision_pairs, &Decimal.add/2),
  "mult high precision" => each_pair.(high_precision_pairs, &Decimal.mult/2),
  "div high precision" => each_pair.(high_precision_pairs, &Decimal.div/2),
  "round" => each.(round_decimals, &Decimal.round(&1, 2, :half_even)),
  "normalize" => each.(decimals, &Decimal.normalize/1),
  "sqrt" => each.(positive_decimals, &Decimal.sqrt/1),
  "to_string scientific" => each.(decimals, &Decimal.to_string(&1, :scientific)),
  "to_string normal" => each.(decimals, &Decimal.to_string(&1, :normal)),
  "new from string" => each.(money_strings, &Decimal.new/1),
  "from_float" => each.(floats, &Decimal.from_float/1),
  "to_float" => each.(float_range_decimals, &Decimal.to_float/1),
  "inspect" => each.(money, &inspect/1),
  "money add" => each_pair.(money_pairs, &Decimal.add/2),
  "money mult" => each_pair.(money_pairs, &Decimal.mult/2),
  "money div" => each_pair.(money_pairs, &Decimal.div/2),
  "money compare" => each_pair.(money_pairs, &Decimal.compare/2),
  "money round" => each.(money, &Decimal.round(&1, 2)),
  "money compare/3" => each_pair.(money_pairs, &Decimal.compare(&1, &2, money_threshold)),
  "money eq?" => each_pair.(money_pairs, &Decimal.eq?/2),
  "money gte?" => each_pair.(money_pairs, &Decimal.gte?/2),
  "money max" => each_pair.(money_pairs, &Decimal.max/2),
  "money min" => each_pair.(money_pairs, &Decimal.min/2),
  "money div_int" => each_pair.(money_pairs, &Decimal.div_int/2),
  "money rem" => each_pair.(money_pairs, &Decimal.rem/2),
  "money div_rem" => each_pair.(money_pairs, &Decimal.div_rem/2),
  "money negate" => each.(money, &Decimal.negate/1),
  "money abs" => each.(money, &Decimal.abs/1),
  "money sqrt" => each.(money, &Decimal.sqrt/1),
  "money integer?" => each.(money, &Decimal.integer?/1),
  "money to_float" => each.(money, &Decimal.to_float/1),
  "money to_string xsd" => each.(money, &Decimal.to_string(&1, :xsd)),
  "money to_string raw" => each.(money, &Decimal.to_string(&1, :raw)),
  "money to_string with limit" => each.(money, &Decimal.to_string(&1, :normal, max_digits: 100)),
  "to_integer" => each.(whole_money, &Decimal.to_integer/1),
  "new from integer" => each.(integers, &Decimal.new/1),
  "new from string with limits" => each.(money_strings, &Decimal.new(&1, max_digits: 40)),
  "parse" => each.(money_strings, &Decimal.parse/1),
  "cast string" => each.(money_strings, &Decimal.cast/1),
  "cast integer" => each.(integers, &Decimal.cast/1),
  "cast float" => each.(floats, &Decimal.cast/1),
  "Context.with" => each.(money, fn _ -> Decimal.Context.with(context, fn -> :ok end) end)
}

load = System.get_env("LOAD", "") |> String.split(",", trim: true)

# Benchee resolves load paths with Path.wildcard, which turns a mistyped path
# into an empty list and a comparison run into a plain one, with no error.
for path <- load, Path.wildcard(path) == [] do
  IO.puts(:stderr, "LOAD path #{path} matches no saved benchmark")
  System.halt(1)
end

Benchee.run(jobs,
  time: 10,
  memory_time: 2,
  save: [path: "benchmarks/#{tag}.benchee", tag: tag],
  load: load,
  formatters: [Benchee.Formatters.Console]
)
