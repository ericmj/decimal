Mix.install([
  {:decimal, path: ".", override: true},
  {:benchee, "~> 1.0"},
  {:benchee_html, "~> 1.0"}
])

{head, 0} = System.cmd("git", ["symbolic-ref", "--short", "HEAD"])
{hash, 0} = System.cmd("git", ["rev-parse", "--short", "HEAD"])

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
  "round" => each.(decimals, &Decimal.round(&1, 2, :half_even)),
  "normalize" => each.(decimals, &Decimal.normalize/1),
  "sqrt" => each.(positive_decimals, &Decimal.sqrt/1),
  "to_string scientific" => each.(decimals, &Decimal.to_string(&1, :scientific)),
  "to_string normal" => each.(decimals, &Decimal.to_string(&1, :normal))
}

Benchee.run(jobs,
  time: 10,
  memory_time: 2,
  save: [path: "benchmarks/#{tag}.benchee", tag: tag],
  formatters: [Benchee.Formatters.Console]
)
