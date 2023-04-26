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
binary_operations = %{"compare" => &Decimal.compare/2}

jobs =
  Map.new(binary_operations, fn {name, fun} ->
    {name, fn -> Enum.each(decimal_pairs, fn {first, second} -> fun.(first, second) end) end}
  end)

Benchee.run(jobs,
  time: 20,
  memory_time: 5,
  save: [path: "benchmarks/#{tag}.benchee", tag: tag],
  formatters: [Benchee.Formatters.Console]
)
