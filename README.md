# Decimal

[![Build Status](https://travis-ci.org/ericmj/decimal.svg?branch=master)](https://travis-ci.org/ericmj/decimal)

Arbitrary precision decimal arithmetic.

## Usage

Add Decimal as a dependency in your `mix.exs` file.

```elixir
def deps do
  [{:decimal, "~> 2.0"}]
end
```

After you are done, run `mix deps.get` in your shell to fetch and compile Decimal. Start an interactive Elixir shell with `iex -S mix`.

```elixir
iex> alias Decimal, as: D
iex> D.add(6, 7)
#Decimal<13>
iex> D.div(1, 3)
#Decimal<0.333333333>
iex> D.new("0.33")
#Decimal<0.33>
```

## Examples

### Using the context

The context specifies the maximum precision of the result of calculations and
the rounding algorithm if the result has a higher precision than the specified
maximum. It also holds the list of set of trap enablers and the currently set
flags.

The context is stored in the process dictionary, this means that you don't have
to pass the context around explicitly and the flags will be updated
automatically.

The context is accessed with `Decimal.Context.get/0` and set with
`Decimal.Context.set/1`. It can also be temporarily set with
`Decimal.Context.with/2`.

```elixir
iex> D.Context.get()
%Decimal.Context{flags: [:rounded, :inexact], precision: 9, rounding: :half_up,
 traps: [:invalid_operation, :division_by_zero]}
iex> D.Context.with(%D.Context{precision: 2}, fn -> IO.inspect D.Context.get() end)
%Decimal.Context{flags: [], precision: 2, rounding: :half_up,
 traps: [:invalid_operation, :division_by_zero]}
%Decimal.Context{flags: [], precision: 2, rounding: :half_up,
 traps: [:invalid_operation, :division_by_zero]}
iex> D.Context.set(%D.Context{D.Context.get() | traps: []})
:ok
iex> D.Context.get()
%Decimal.Context{flags: [:rounded, :inexact], precision: 9, rounding: :half_up,
 traps: []}
```

### Precision and rounding

The precision is used to limit the amount of decimal digits in the coefficient:

```elixir
iex> D.Context.set(%D.Context{D.Context.get() | precision: 9})
:ok
iex> D.div(100, 3)
#Decimal<33.3333333>
iex> D.Context.set(%D.Context{D.Context.get() | precision: 2})
:ok
iex> D.div(100, 3)
#Decimal<33>
```

The rounding algorithm specifies how the result of an operation shall be rounded
when it get be represented with the current precision:

```elixir
iex> D.Context.set(%D.Context{D.Context.get() | rounding: :half_up})
:ok
iex> D.div(31, 2)
#Decimal<16>
iex> D.Context.set(%D.Context{D.Context.get() | rounding: :floor})
:ok
iex> D.div(31, 2)
#Decimal<15>
```

### Comparisons

Using compare operators (`<`, `=`, `>`) directly with two decimals may not return
the correct result. Instead use comparison functions.

```elixir
iex> D.compare(-1, 0)
:lt
iex> D.compare(0, -1)
:gt
iex> D.compare(0, 0)
:eq

iex> D.equal?(-1, 0)
false
iex> D.equal?(0, "0.0")
true
```

### Flags and trap enablers

When an exceptional condition is signalled its flag is set in the context and if
if the trap enabler is set `Decimal.Error` will be raised.

```elixir
iex> D.Context.set(%D.Context{D.Context.get() | rounding: :floor, precision: 2})
:ok
iex> D.Context.get().traps
[:invalid_operation, :division_by_zero]
iex> D.Context.get().flags
[]
iex> D.div(31, 2)
#Decimal<15>
iex> D.Context.get().flags
[:inexact, :rounded]
```

`:inexact` and `:rounded` were signaled above because the result of the
operation was inexact given the context's precision and had to be rounded to fit
the precision. `Decimal.Error` was not raised because the signals' trap enablers
weren't set. We can, however, set the trap enabler if we what this condition to
raise.

```elixir
iex> D.Context.set(%D.Context{D.Context.get() | traps: D.Context.get().traps ++ [:inexact]})
:ok
iex> D.div(31, 2)
** (Decimal.Error)
```

The default trap enablers, such as `:division_by_zero` can be unset:

```elixir
iex> D.Context.get().traps
[:invalid_operation, :division_by_zero]
iex> D.div(42, 0)
** (Decimal.Error)
iex> D.Context.set(%D.Context{D.Context.get() | traps: [], flags: []})
:ok
iex> D.div(42, 0)
#Decimal<Infinity>
iex> D.Context.get().flags
[:division_by_zero]
```

### Mitigating rounding errors

TODO

## License

   Copyright 2013 Eric Meadows-Jönsson

   Licensed under the Apache License, Version 2.0 (the "License");
   you may not use this file except in compliance with the License.
   You may obtain a copy of the License at

       http://www.apache.org/licenses/LICENSE-2.0

   Unless required by applicable law or agreed to in writing, software
   distributed under the License is distributed on an "AS IS" BASIS,
   WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
   See the License for the specific language governing permissions and
   limitations under the License.
